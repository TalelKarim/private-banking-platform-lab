#!/usr/bin/env bash
set -euxo pipefail
exec > >(tee -a /var/log/private-banking-lab-edge-gateway-bootstrap.log | logger -t private-banking-lab-edge-gateway -s 2>/dev/console) 2>&1
export DEBIAN_FRONTEND=noninteractive

echo "=== Starting private banking lab edge-gateway bootstrap ==="
hostnamectl set-hostname edge-gateway
if grep -qE '^127\.0\.1\.1[[:space:]]+' /etc/hosts; then
  sed -i -E 's/^127\.0\.1\.1[[:space:]].*/127.0.1.1 edge-gateway/' /etc/hosts
else
  printf '127.0.1.1 edge-gateway\n' >> /etc/hosts
fi
apt-get update
apt-get install -y ca-certificates curl openssh-server python3 python3-apt ec2-instance-connect 
systemctl enable --now ssh
systemctl enable --now snap.amazon-ssm-agent.amazon-ssm-agent.service || systemctl enable --now amazon-ssm-agent || true
cat > /etc/motd <<'EOF'
============================================================
 Private Banking Platform Lab - Edge Gateway
============================================================
 Role      : HTTP/HTTPS ingress and reverse proxy
 Nginx     : managed by Ansible
 Backends  : OpenStack floating IPs / future ingress VIPs
 Bootstrap : /var/log/private-banking-lab-edge-gateway-bootstrap.log
============================================================
EOF
python3 --version
echo "=== Private banking lab edge-gateway bootstrap completed ==="
