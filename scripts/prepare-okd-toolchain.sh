#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CLUSTER_CONFIG="$ROOT_DIR/platform/openshift/cluster-config.yml"
INSTALL_ROOT=${OKD_TOOLCHAIN_ROOT:-/opt/private-banking-okd}

read_config_value() {
  local key=$1
  awk -F': *' -v wanted="$key" '$1 == wanted {print $2; exit}' "$CLUSTER_CONFIG"
}

OKD_VERSION=${OKD_VERSION:-$(read_config_value okd_release_version)}
OKD_ARCHITECTURE=${OKD_ARCHITECTURE:-$(read_config_value okd_architecture)}

if [[ -z "$OKD_VERSION" || -z "$OKD_ARCHITECTURE" ]]; then
  echo "Missing okd_release_version/okd_architecture in $CLUSTER_CONFIG" >&2
  exit 1
fi

if [[ "$OKD_ARCHITECTURE" != "x86_64" ]]; then
  echo "This lab currently supports only x86_64 OKD tooling; got: $OKD_ARCHITECTURE" >&2
  exit 1
fi

for binary in curl tar sha256sum sudo; do
  command -v "$binary" >/dev/null 2>&1 || {
    echo "Required command not found: $binary" >&2
    exit 1
  }
done

VERSION_DIR="$INSTALL_ROOT/$OKD_VERSION"
INSTALLER_BIN="$VERSION_DIR/openshift-install"
OC_BIN="$VERSION_DIR/oc"
KUBECTL_BIN="$VERSION_DIR/kubectl"

is_expected_version() {
  [[ -x "$INSTALLER_BIN" ]] && \
    "$INSTALLER_BIN" version 2>/dev/null | grep -Fq "$OKD_VERSION" && \
    [[ -x "$OC_BIN" ]] && [[ -x "$KUBECTL_BIN" ]]
}

if is_expected_version; then
  echo "OKD toolchain already prepared: $OKD_VERSION"
else
  RELEASE_BASE_URL="https://github.com/okd-project/okd/releases/download/$OKD_VERSION"
  INSTALLER_ARCHIVE="openshift-install-linux-$OKD_VERSION.tar.gz"
  CLIENT_ARCHIVE="openshift-client-linux-$OKD_VERSION.tar.gz"
  CHECKSUM_FILE="sha256sum.txt"
  TMP_DIR=$(mktemp -d /tmp/private-banking-okd-tools.XXXXXX)
  trap 'rm -rf "$TMP_DIR"' EXIT

  echo "Downloading pinned OKD toolchain: $OKD_VERSION"
  curl -fsSL --retry 3 --retry-delay 2 \
    -o "$TMP_DIR/$CHECKSUM_FILE" \
    "$RELEASE_BASE_URL/$CHECKSUM_FILE"

  for archive in "$INSTALLER_ARCHIVE" "$CLIENT_ARCHIVE"; do
    curl -fsSL --retry 3 --retry-delay 2 \
      -o "$TMP_DIR/$archive" \
      "$RELEASE_BASE_URL/$archive"

    checksum_line=$(grep -E "[ *]${archive}$" "$TMP_DIR/$CHECKSUM_FILE" || true)
    if [[ -z "$checksum_line" ]]; then
      echo "No checksum published for $archive in $CHECKSUM_FILE" >&2
      exit 1
    fi

    (
      cd "$TMP_DIR"
      printf '%s\n' "$checksum_line" | sha256sum -c -
    )
  done

  mkdir -p "$TMP_DIR/installer" "$TMP_DIR/client"
  tar -xzf "$TMP_DIR/$INSTALLER_ARCHIVE" -C "$TMP_DIR/installer"
  tar -xzf "$TMP_DIR/$CLIENT_ARCHIVE" -C "$TMP_DIR/client"

  for file in \
    "$TMP_DIR/installer/openshift-install" \
    "$TMP_DIR/client/oc" \
    "$TMP_DIR/client/kubectl"; do
    [[ -f "$file" ]] || {
      echo "Expected binary missing from OKD release archive: $file" >&2
      exit 1
    }
  done

  sudo install -d -m 0755 "$VERSION_DIR"
  sudo install -m 0755 "$TMP_DIR/installer/openshift-install" "$INSTALLER_BIN"
  sudo install -m 0755 "$TMP_DIR/client/oc" "$OC_BIN"
  sudo install -m 0755 "$TMP_DIR/client/kubectl" "$KUBECTL_BIN"
fi

sudo ln -sfn "$INSTALLER_BIN" /usr/local/bin/openshift-install
sudo ln -sfn "$OC_BIN" /usr/local/bin/oc
sudo ln -sfn "$KUBECTL_BIN" /usr/local/bin/kubectl

if ! openshift-install version | grep -Fq "$OKD_VERSION"; then
  echo "openshift-install does not match pinned release $OKD_VERSION" >&2
  openshift-install version >&2 || true
  exit 1
fi

printf '\nPinned OKD toolchain ready:\n'
openshift-install version | sed -n '1,4p'
printf 'oc:      %s\n' "$(command -v oc)"
printf 'kubectl: %s\n' "$(command -v kubectl)"
