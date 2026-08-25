#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
POSTGRESQL_SERVER_NAME=${POSTGRESQL_SERVER_NAME:-postgresql}
POSTGRESQL_FLOATING_IP=${POSTGRESQL_FLOATING_IP:-}
WORKLOAD_KEY=/home/ubuntu/.ssh/private-banking-openstack-workloads
ACTION=${1:-}
BACKUP=${BACKUP:-latest}
TARGET_DB=${TARGET_DB:-portfolio_restore_manual}
CONFIRM=${CONFIRM:-}

usage() {
  cat >&2 <<'USAGE'
Usage: postgresql-backup.sh <backup|list|test-restore|restore>

Optional environment variables:
  POSTGRESQL_FLOATING_IP=192.168.250.x
  BACKUP=portfolio_YYYYMMDDTHHMMSSZ.dump|latest
  TARGET_DB=portfolio_restore_manual
  CONFIRM=RESTORE_portfolio    # required only to replace the live DB
USAGE
  exit 2
}

case "$ACTION" in
  backup|list|test-restore|restore) ;;
  *) usage ;;
esac

for binary in ssh python3; do
  command -v "$binary" >/dev/null 2>&1 || {
    echo "Required command not found: $binary" >&2
    exit 1
  }
done

if [[ ! -r "$WORKLOAD_KEY" || "$(stat -c '%a' "$WORKLOAD_KEY")" != "600" ]]; then
  echo "Missing or insecure workload SSH key: $WORKLOAD_KEY" >&2
  exit 1
fi

if [[ -z "$POSTGRESQL_FLOATING_IP" ]]; then
  printf 'Discovering PostgreSQL floating IP...\n'
  POSTGRESQL_FLOATING_IP=$(
    "$ROOT_DIR/scripts/discover-openstack-floating-ip.sh" "$POSTGRESQL_SERVER_NAME"
  )
fi

python3 - "$POSTGRESQL_FLOATING_IP" <<'PY'
import ipaddress
import sys
ipaddress.IPv4Address(sys.argv[1])
PY

[[ "$BACKUP" == "latest" || "$BACKUP" =~ ^portfolio_[0-9]{8}T[0-9]{6}Z\.dump$ ]] || {
  echo "Invalid BACKUP value: $BACKUP" >&2
  exit 2
}
[[ "$TARGET_DB" =~ ^[a-z][a-z0-9_]*$ ]] || {
  echo "Invalid TARGET_DB value: $TARGET_DB" >&2
  exit 2
}
[[ -z "$CONFIRM" || "$CONFIRM" == "RESTORE_portfolio" ]] || {
  echo "Invalid CONFIRM value." >&2
  exit 2
}

KNOWN_HOSTS=$(mktemp /tmp/private-banking-postgresql-backup-known-hosts.XXXXXX)
trap 'rm -f "$KNOWN_HOSTS"' EXIT

SSH_OPTS=(
  -i "$WORKLOAD_KEY"
  -o BatchMode=yes
  -o ConnectTimeout=5
  -o StrictHostKeyChecking=accept-new
  -o UserKnownHostsFile="$KNOWN_HOSTS"
)
REMOTE="ubuntu@${POSTGRESQL_FLOATING_IP}"

case "$ACTION" in
  backup)
    printf 'Creating PostgreSQL logical backup on persistent Cinder storage...\n'
    ssh "${SSH_OPTS[@]}" "$REMOTE" \
      'sudo -u postgres /usr/local/sbin/private-banking-postgresql-backup'
    ;;
  list)
    printf 'Retained PostgreSQL backups:\n'
    ssh "${SSH_OPTS[@]}" "$REMOTE" \
      "sudo -u postgres find /var/lib/postgresql/backups -maxdepth 1 -type f -name 'portfolio_*.dump' -printf '%f\\n' | sort"
    ;;
  test-restore)
    printf 'Restoring %s into an isolated temporary database and validating it...\n' "$BACKUP"
    ssh "${SSH_OPTS[@]}" "$REMOTE" \
      "sudo -u postgres /usr/local/sbin/private-banking-postgresql-test-restore '$BACKUP'"
    ;;
  restore)
    if [[ "$TARGET_DB" == "portfolio" && "$CONFIRM" != "RESTORE_portfolio" ]]; then
      echo "Refusing live restore. Use CONFIRM=RESTORE_portfolio deliberately." >&2
      exit 2
    fi
    printf 'Restoring %s into PostgreSQL database %s...\n' "$BACKUP" "$TARGET_DB"
    ssh "${SSH_OPTS[@]}" "$REMOTE" \
      "sudo -u postgres /usr/local/sbin/private-banking-postgresql-restore '$BACKUP' '$TARGET_DB' '$CONFIRM'"
    ;;
esac
