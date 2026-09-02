#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
AWS_REGION=${AWS_REGION:-eu-south-2}
JENKINS_SERVER_NAME=${JENKINS_SERVER_NAME:-jenkins-controller}
JENKINS_FLOATING_IP=${1:-${JENKINS_FLOATING_IP:-}}
JENKINS_ADMIN_USERNAME=${JENKINS_ADMIN_USERNAME:-admin}
JENKINS_ADMIN_PASSWORD_PARAMETER=${JENKINS_ADMIN_PASSWORD_PARAMETER:-/private-banking-platform-lab/jenkins/admin-password}
JENKINS_SMOKE_JOB=${JENKINS_OPENSHIFT_SMOKE_JOB:-platform-openshift-smoke}
JENKINS_BUILD_TIMEOUT_SECONDS=${JENKINS_OPENSHIFT_BUILD_TIMEOUT_SECONDS:-900}
WORKLOAD_KEY=/home/ubuntu/.ssh/private-banking-openstack-workloads
KUBECONFIG=${KUBECONFIG:-$ROOT_DIR/.runtime/openshift/install/auth/kubeconfig}

for binary in aws python3 ssh scp oc; do
  command -v "$binary" >/dev/null 2>&1 || { echo "Required command not found: $binary" >&2; exit 1; }
done
[[ -r "$KUBECONFIG" ]] || { echo "Missing OKD kubeconfig: $KUBECONFIG" >&2; exit 1; }
export KUBECONFIG

if [[ ! -r "$WORKLOAD_KEY" || "$(stat -c '%a' "$WORKLOAD_KEY")" != "600" ]]; then
  echo "Missing or insecure workload SSH key: $WORKLOAD_KEY" >&2
  exit 1
fi

if [[ -z "$JENKINS_FLOATING_IP" ]]; then
  JENKINS_FLOATING_IP=$(
    "$ROOT_DIR/scripts/discover-openstack-floating-ip.sh" "$JENKINS_SERVER_NAME"
  )
fi

LOCAL_AUTH_FILE=$(mktemp /tmp/private-banking-jenkins-openshift-auth.XXXXXX)
KNOWN_HOSTS=$(mktemp /tmp/private-banking-jenkins-openshift-known-hosts.XXXXXX)
REMOTE_AUTH_FILE="/tmp/private-banking-jenkins-openshift-auth.$$"
cleanup() {
  ssh -i "$WORKLOAD_KEY" -o BatchMode=yes -o ConnectTimeout=5 \
    -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$KNOWN_HOSTS" \
    "ubuntu@${JENKINS_FLOATING_IP}" "rm -f '$REMOTE_AUTH_FILE'" >/dev/null 2>&1 || true
  rm -f "$LOCAL_AUTH_FILE" "$KNOWN_HOSTS"
}
trap cleanup EXIT

chmod 0600 "$LOCAL_AUTH_FILE"
printf '%s:' "$JENKINS_ADMIN_USERNAME" > "$LOCAL_AUTH_FILE"
aws ssm get-parameter \
  --region "$AWS_REGION" \
  --name "$JENKINS_ADMIN_PASSWORD_PARAMETER" \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text >> "$LOCAL_AUTH_FILE"

SSH_OPTS=(
  -i "$WORKLOAD_KEY"
  -o BatchMode=yes
  -o ConnectTimeout=5
  -o StrictHostKeyChecking=accept-new
  -o UserKnownHostsFile="$KNOWN_HOSTS"
)
scp "${SSH_OPTS[@]}" "$LOCAL_AUTH_FILE" "ubuntu@${JENKINS_FLOATING_IP}:${REMOTE_AUTH_FILE}"
ssh "${SSH_OPTS[@]}" "ubuntu@${JENKINS_FLOATING_IP}" "chmod 0600 '$REMOTE_AUTH_FILE'"

printf 'Triggering Jenkins/OpenShift end-to-end smoke job %s...\n' "$JENKINS_SMOKE_JOB"
ssh "${SSH_OPTS[@]}" "ubuntu@${JENKINS_FLOATING_IP}" \
  python3 - \
  "http://127.0.0.1:8080" \
  "$REMOTE_AUTH_FILE" \
  "$JENKINS_SMOKE_JOB" \
  "$JENKINS_BUILD_TIMEOUT_SECONDS" <<'PY'
import base64
import http.cookiejar
import json
import pathlib
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

base_url, auth_file, job_name, timeout_raw = sys.argv[1:]
timeout = int(timeout_raw)
credentials = pathlib.Path(auth_file).read_text().strip()
auth = base64.b64encode(credentials.encode()).decode()
base_headers = {"Authorization": f"Basic {auth}"}
# Jenkins' default crumb issuer can bind the crumb to the HTTP session.
# Keep cookies (notably JSESSIONID) between the crumb request and the POST.
cookie_jar = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cookie_jar))


def request_json(url, method="GET", headers=None):
    request_headers = dict(base_headers)
    if headers:
        request_headers.update(headers)
    req = urllib.request.Request(url, headers=request_headers, method=method)
    with opener.open(req, timeout=15) as response:
        body = response.read()
        return response, json.loads(body.decode()) if body else None


crumb_headers = {}
try:
    _, crumb = request_json(f"{base_url}/crumbIssuer/api/json")
    crumb_headers[crumb["crumbRequestField"]] = crumb["crumb"]
except urllib.error.HTTPError as exc:
    if exc.code != 404:
        raise

job_path = urllib.parse.quote(job_name, safe="")
req = urllib.request.Request(
    f"{base_url}/job/{job_path}/build",
    headers={**base_headers, **crumb_headers},
    method="POST",
)
try:
    with opener.open(req, timeout=15) as response:
        queue_url = response.headers.get("Location")
except urllib.error.HTTPError as exc:
    raise SystemExit(f"Unable to trigger Jenkins job: HTTP {exc.code}: {exc.read().decode(errors='replace')}")

if not queue_url:
    raise SystemExit("Jenkins did not return a queue Location header.")
queue_url = urllib.parse.urljoin(base_url + "/", queue_url)
deadline = time.monotonic() + timeout
build_number = None
while time.monotonic() < deadline:
    _, queue = request_json(queue_url.rstrip("/") + "/api/json")
    if queue.get("cancelled"):
        raise SystemExit("Jenkins cancelled the OpenShift smoke job while queued.")
    if queue.get("executable"):
        build_number = queue["executable"]["number"]
        break
    time.sleep(2)
if build_number is None:
    raise SystemExit("Timed out waiting for Jenkins to assign the OpenShift smoke job.")

print(f"OpenShift smoke build assigned: #{build_number}")
build_api = f"{base_url}/job/{job_path}/{build_number}/api/json"
while time.monotonic() < deadline:
    _, build = request_json(build_api)
    if not build.get("building", False):
        result = build.get("result")
        print(f"OpenShift smoke build result: {result}")
        if result != "SUCCESS":
            console_url = f"{base_url}/job/{job_path}/{build_number}/consoleText"
            try:
                req = urllib.request.Request(console_url, headers=base_headers)
                with opener.open(req, timeout=15) as response:
                    text = response.read().decode(errors="replace")
                print("----- Jenkins console tail -----")
                print("\n".join(text.splitlines()[-120:]))
            except Exception as exc:
                print(f"Unable to retrieve Jenkins console output: {exc}")
            raise SystemExit(f"Jenkins/OpenShift smoke build failed with result {result}.")
        raise SystemExit(0)
    time.sleep(3)
raise SystemExit("Timed out waiting for Jenkins/OpenShift smoke build to finish.")
PY

printf 'Validating the workload created by Jenkins inside OpenShift...\n'
oc rollout status deployment/phase2-smoke -n demo --timeout=2m
oc get imagestream phase2-smoke -n demo
oc get pods -n demo -l app=phase2-smoke -o wide

printf '\nJENKINS <-> OPENSHIFT END-TO-END SMOKE: SUCCESS\n'
