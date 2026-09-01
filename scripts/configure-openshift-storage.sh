#!/usr/bin/env bash
set -euo pipefail
umask 077

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CLUSTER_CONFIG="$ROOT_DIR/platform/openshift/cluster-config.yml"
KUBECONFIG=${KUBECONFIG:-$ROOT_DIR/.runtime/openshift/install/auth/kubeconfig}
ANSIBLE_PYTHON=${ANSIBLE_PYTHON:-/opt/ansible-venv/bin/python}
AWS_REGION=${AWS_REGION:-eu-south-2}
LAB_HOST_PRIVATE_IP=${LAB_HOST_PRIVATE_IP:-172.31.31.70}
LAB_HOST_SSH_USER=${LAB_HOST_SSH_USER:-ubuntu}
LAB_SSH_KEY_PARAMETER=${LAB_SSH_KEY_PARAMETER:-/private-banking-platform-lab/aws/lab-ssh-private-key}
OPENSTACK_CLIENT=${OPENSTACK_CLIENT:-/opt/openstack-client-venv/bin/openstack}
OPENSTACK_CLOUDS_FILE=${OPENSTACK_CLOUDS_FILE:-/data/openstack/secrets/clouds.yaml}
OPENSTACK_CLOUD=${OPENSTACK_CLOUD:-kolla-admin}

for binary in aws ssh oc helm jq openssl "$ANSIBLE_PYTHON"; do
  if [[ "$binary" == */* ]]; then
    [[ -x "$binary" ]] || { echo "Missing executable: $binary" >&2; exit 1; }
  else
    command -v "$binary" >/dev/null 2>&1 || { echo "Missing command: $binary" >&2; exit 1; }
  fi
done
[[ -r "$KUBECONFIG" ]] || { echo "Missing OKD kubeconfig: $KUBECONFIG" >&2; exit 1; }
export KUBECONFIG

CONFIG_JSON=$(
  "$ANSIBLE_PYTHON" - "$CLUSTER_CONFIG" <<'PY'
import json, sys, yaml
with open(sys.argv[1], encoding='utf-8') as f:
    print(json.dumps(yaml.safe_load(f)))
PY
)

CLUSTER_NAME=$(jq -r '.okd_cluster_name' <<<"$CONFIG_JSON")
BASE_DOMAIN=$(jq -r '.okd_base_domain' <<<"$CONFIG_JSON")
CSI_CHART_VERSION=$(jq -r '.okd_cinder_csi_chart_version' <<<"$CONFIG_JSON")
STORAGE_CLASS=$(jq -r '.okd_cinder_storage_class' <<<"$CONFIG_JSON")
OS_PROJECT=$(jq -r '.okd_cinder_openstack_project' <<<"$CONFIG_JSON")
OS_USER=$(jq -r '.okd_cinder_openstack_user' <<<"$CONFIG_JSON")
OS_ROLE=$(jq -r '.okd_cinder_openstack_role' <<<"$CONFIG_JSON")
OS_REGION=$(jq -r '.okd_openstack_region' <<<"$CONFIG_JSON")
PASSWORD_PARAMETER=$(jq -r '.okd_cinder_password_ssm_parameter' <<<"$CONFIG_JSON")

SSH_KEY=$(mktemp /tmp/private-banking-lab-host-key.XXXXXX)
KNOWN_HOSTS=$(mktemp /tmp/private-banking-lab-host-known-hosts.XXXXXX)
CLOUD_CONF=$(mktemp /tmp/private-banking-cinder-cloud.XXXXXX)
SMOKE_MANIFEST=$(mktemp /tmp/private-banking-cinder-smoke.XXXXXX.yaml)
STORAGE_READY_MARKER="$ROOT_DIR/.runtime/openshift/storage-foundation.ready"
trap 'rm -f "$SSH_KEY" "$KNOWN_HOSTS" "$CLOUD_CONF" "$SMOKE_MANIFEST"' EXIT

aws ssm get-parameter \
  --region "$AWS_REGION" \
  --name "$LAB_SSH_KEY_PARAMETER" \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text > "$SSH_KEY"
chmod 0600 "$SSH_KEY"

SSH_OPTS=(
  -i "$SSH_KEY"
  -o BatchMode=yes
  -o ConnectTimeout=5
  -o StrictHostKeyChecking=accept-new
  -o UserKnownHostsFile="$KNOWN_HOSTS"
)

remote_openstack() {
  local remote_cmd
  printf -v remote_cmd '%q ' \
    env "OS_CLIENT_CONFIG_FILE=$OPENSTACK_CLOUDS_FILE" \
    "$OPENSTACK_CLIENT" --os-cloud "$OPENSTACK_CLOUD" "$@"
  ssh "${SSH_OPTS[@]}" "${LAB_HOST_SSH_USER}@${LAB_HOST_PRIVATE_IP}" "$remote_cmd"
}

remote_openstack token issue -f value -c id >/dev/null

printf '==> Ensuring a runtime-only OpenStack credential for Cinder CSI\n'
if ! CINDER_PASSWORD=$(aws ssm get-parameter \
    --region "$AWS_REGION" \
    --name "$PASSWORD_PARAMETER" \
    --with-decryption \
    --query 'Parameter.Value' \
    --output text 2>/dev/null); then
  CINDER_PASSWORD=$(openssl rand -base64 48 | tr -d '\n')
  aws ssm put-parameter \
    --region "$AWS_REGION" \
    --name "$PASSWORD_PARAMETER" \
    --type SecureString \
    --value "$CINDER_PASSWORD" \
    --overwrite >/dev/null
  printf '    Created SecureString %s\n' "$PASSWORD_PARAMETER"
else
  printf '    Reusing SecureString %s\n' "$PASSWORD_PARAMETER"
fi

if remote_openstack user show "$OS_USER" -f value -c id >/dev/null 2>&1; then
  remote_openstack user set --password "$CINDER_PASSWORD" "$OS_USER" >/dev/null
else
  remote_openstack user create \
    --domain Default \
    --password "$CINDER_PASSWORD" \
    "$OS_USER" >/dev/null
fi

# role add is idempotent when the assignment already exists.
remote_openstack role add --project "$OS_PROJECT" --user "$OS_USER" "$OS_ROLE" >/dev/null

endpoint_url() {
  local service_type=$1
  remote_openstack endpoint list \
    --service "$service_type" \
    --interface public \
    -f value -c URL | awk 'NF {print $1; exit}'
}

AUTH_URL=$(endpoint_url identity)
NOVA_URL=$(endpoint_url compute)
CINDER_URL=$(endpoint_url volumev3)
[[ -n "$AUTH_URL" ]] || { echo "Unable to discover the Keystone public endpoint." >&2; exit 1; }
[[ -n "$NOVA_URL" ]] || { echo "Unable to discover the Nova public endpoint." >&2; exit 1; }
[[ -n "$CINDER_URL" ]] || { echo "Unable to discover the Cinder v3 public endpoint." >&2; exit 1; }

cat > "$CLOUD_CONF" <<EOF_CLOUD
[Global]
auth-url=$AUTH_URL
username=$OS_USER
password=$CINDER_PASSWORD
tenant-name=$OS_PROJECT
domain-name=Default
region=$OS_REGION

[BlockStorage]
rescan-on-resize=true

[Metadata]
search-order=configDrive,metadataService
EOF_CLOUD
chmod 0600 "$CLOUD_CONF"
unset CINDER_PASSWORD

printf '==> Validating OKD node reachability to the OpenStack APIs required by Cinder CSI\n'
# Any HTTP response proves L3/L4 reachability; 401/403 are expected for these
# unauthenticated probes. Cinder CSI needs all three APIs, not only Keystone.
for endpoint_spec in \
  "Keystone|$AUTH_URL" \
  "Nova|$NOVA_URL" \
  "Cinder|$CINDER_URL"; do
  IFS='|' read -r endpoint_name endpoint_url_value <<<"$endpoint_spec"
  HTTP_CODE=$(oc debug node/okd-01 --quiet -- chroot /host \
    curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 "$endpoint_url_value" \
    2>/dev/null | tail -n1 || true)
  if [[ ! "$HTTP_CODE" =~ ^(2|3|4)[0-9][0-9]$ ]]; then
    echo "OKD node -> $endpoint_name connectivity failed for $endpoint_url_value (HTTP code: ${HTTP_CODE:-none})." >&2
    exit 1
  fi
  printf '    %-10s reachable (%s, HTTP %s)\n' "$endpoint_name" "$endpoint_url_value" "$HTTP_CODE"
done

printf '==> Creating/updating Cinder CSI cloud.conf Secret\n'
oc -n kube-system create secret generic cinder-csi-cloud-config \
  --from-file=cloud.conf="$CLOUD_CONF" \
  --dry-run=client -o yaml | oc apply -f -

printf '==> Granting only the Cinder node plugin access to the privileged SCC\n'
oc apply -f "$ROOT_DIR/platform/openshift/storage/cinder-csi-scc.yaml"

printf '==> Installing pinned OpenStack Cinder CSI chart %s\n' "$CSI_CHART_VERSION"
helm repo add cpo https://kubernetes.github.io/cloud-provider-openstack --force-update >/dev/null
helm repo update cpo >/dev/null
helm upgrade --install cinder-csi cpo/openstack-cinder-csi \
  --namespace kube-system \
  --version "$CSI_CHART_VERSION" \
  --values "$ROOT_DIR/platform/openshift/storage/cinder-csi-values.yaml" \
  --set-string "clusterID=${CLUSTER_NAME}.${BASE_DOMAIN}" \
  --wait \
  --timeout 10m

printf '==> Converging default StorageClass %s\n' "$STORAGE_CLASS"
# The manifest is intentionally named cinder-standard; fail instead of silently
# diverging if cluster-config.yml is changed without updating the contract.
[[ "$STORAGE_CLASS" == "cinder-standard" ]] || {
  echo "cluster-config.yml requests '$STORAGE_CLASS' but the committed StorageClass manifest is cinder-standard." >&2
  exit 1
}
oc apply -f "$ROOT_DIR/platform/openshift/storage/cinder-standard.yaml"

printf '==> Verifying CSI registration after Helm --wait\n'
oc get csidriver cinder.csi.openstack.org >/dev/null

printf '==> End-to-end Cinder smoke test: PVC -> Cinder volume -> node attachment\n'
cat > "$SMOKE_MANIFEST" <<EOF_SMOKE
apiVersion: v1
kind: Namespace
metadata:
  name: storage-smoke
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: cinder-smoke
  namespace: storage-smoke
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: $STORAGE_CLASS
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: cinder-smoke
  namespace: storage-smoke
spec:
  restartPolicy: Never
  containers:
    - name: smoke
      image: registry.access.redhat.com/ubi9/ubi-minimal:9.6
      command: ["/bin/sh", "-c", "echo cinder-csi-ok > /data/probe && cat /data/probe && sleep 20"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: cinder-smoke
EOF_SMOKE

# Always remove the smoke resources so daily runs remain clean. The StorageClass
# reclaimPolicy=Delete asks Cinder to remove the temporary volume too.
oc apply -f "$SMOKE_MANIFEST" >/dev/null
smoke_ok=false
for _ in $(seq 1 120); do
  pvc_phase=$(oc get pvc cinder-smoke -n storage-smoke -o jsonpath='{.status.phase}' 2>/dev/null || true)
  pod_phase=$(oc get pod cinder-smoke -n storage-smoke -o jsonpath='{.status.phase}' 2>/dev/null || true)
  if [[ "$pvc_phase" == "Bound" && ( "$pod_phase" == "Running" || "$pod_phase" == "Succeeded" ) ]]; then
    smoke_ok=true
    break
  fi
  if [[ "$pod_phase" == "Failed" ]]; then
    break
  fi
  sleep 3
done

if [[ "$smoke_ok" != true ]]; then
  echo "Cinder smoke test failed." >&2
  oc describe pvc cinder-smoke -n storage-smoke >&2 || true
  oc describe pod cinder-smoke -n storage-smoke >&2 || true
  oc get events -n storage-smoke --sort-by=.lastTimestamp >&2 || true
  oc delete namespace storage-smoke --wait=false >/dev/null 2>&1 || true
  exit 1
fi

oc delete namespace storage-smoke --wait=true --timeout=3m >/dev/null

mkdir -p "$(dirname "$STORAGE_READY_MARKER")"
printf 'cinder.csi.openstack.org\n' > "$STORAGE_READY_MARKER"
chmod 0600 "$STORAGE_READY_MARKER"

printf '\nOpenShift persistent storage READY:\n'
printf '  %-24s %s\n' 'CSI driver' 'cinder.csi.openstack.org'
printf '  %-24s %s\n' 'StorageClass' "$STORAGE_CLASS (default)"
printf '  %-24s %s\n' 'OpenStack project/user' "$OS_PROJECT / $OS_USER"
printf '  %-24s %s\n' 'Dynamic provisioning' 'validated end-to-end'
