# Versioned Ready AMI checkpoint for the current validated lab.
# These AMI IDs are account/region-specific and contain no secrets.
#
# lab-host: root + /data + Cinder snapshots with OpenStack state preserved.
golden_ami_id = "ami-010466df42142aa9e"

# edge-gateway: configured root filesystem / Nginx checkpoint.
edge_gateway_ami_id = "ami-0a90d8433dee8e9a9"

# Keep the baked endpoints on the stable addresses expected by the lab.
openstack_host_private_ip = "172.31.31.70"
edge_gateway_private_ip   = "172.31.31.71"
