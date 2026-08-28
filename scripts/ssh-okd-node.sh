#!/usr/bin/env bash
set -euo pipefail
NODE=${1:-}
case "$NODE" in
  bootstrap|okd-01|okd-02|okd-03) ;;
  *) echo "Usage: $0 bootstrap|okd-01|okd-02|okd-03" >&2; exit 2 ;;
esac
exec ssh "$NODE"
