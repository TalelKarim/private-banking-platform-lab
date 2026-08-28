module "jenkins_controller" {
  source = "./modules/compute-instance"

  # A floating IP can only be associated once Neutron has a complete path
  # from the private subnet to the external network through the router.
  depends_on = [openstack_networking_router_interface_v2.private]

  name       = var.jenkins_instance_name
  image_id   = openstack_images_image_v2.ubuntu_2404.id
  flavor_id  = openstack_compute_flavor_v2.medium.id
  key_pair   = openstack_compute_keypair_v2.workload.name
  network_id = openstack_networking_network_v2.private.id
  subnet_id  = openstack_networking_subnet_v2.private.id
  fixed_ip   = var.jenkins_fixed_ip

  security_group_ids = [
    openstack_networking_secgroup_v2.management.id,
    openstack_networking_secgroup_v2.jenkins.id,
  ]

  create_floating_ip  = true
  external_network    = openstack_networking_network_v2.external.name
  external_subnet_id  = openstack_networking_subnet_v2.external.id
  data_volume_size_gb = var.jenkins_data_volume_size_gb

  metadata = {
    environment = "lab"
    role        = "jenkins-controller"
    managed_by  = "terraform"
  }

  tags = [
    "lab",
    "jenkins",
    "platform",
  ]
}

module "jenkins_worker" {
  source = "./modules/compute-instance"

  # The worker receives a Floating IP only for ops-runner/Ansible management.
  # Jenkins Remoting itself uses the private OpenStack network.
  depends_on = [openstack_networking_router_interface_v2.private]

  name       = var.jenkins_worker_instance_name
  image_id   = openstack_images_image_v2.ubuntu_2404.id
  flavor_id  = openstack_compute_flavor_v2.medium.id
  key_pair   = openstack_compute_keypair_v2.workload.name
  network_id = openstack_networking_network_v2.private.id
  subnet_id  = openstack_networking_subnet_v2.private.id
  fixed_ip   = var.jenkins_worker_fixed_ip

  security_group_ids = [
    openstack_networking_secgroup_v2.management.id,
    openstack_networking_secgroup_v2.jenkins_worker.id,
  ]

  create_floating_ip = true
  external_network   = openstack_networking_network_v2.external.name
  external_subnet_id = openstack_networking_subnet_v2.external.id

  metadata = {
    environment = "lab"
    role        = "jenkins-worker"
    managed_by  = "terraform"
  }

  tags = [
    "lab",
    "jenkins",
    "worker",
    "platform",
  ]
}

module "postgresql" {
  source = "./modules/compute-instance"

  # The floating IP is management-only: ops-runner/Ansible reaches SSH through
  # the provider network. PostgreSQL/5432 itself stays private to 10.10.0.0/24.
  depends_on = [openstack_networking_router_interface_v2.private]

  name       = var.postgresql_instance_name
  image_id   = openstack_images_image_v2.ubuntu_2404.id
  flavor_id  = openstack_compute_flavor_v2.medium.id
  key_pair   = openstack_compute_keypair_v2.workload.name
  network_id = openstack_networking_network_v2.private.id
  subnet_id  = openstack_networking_subnet_v2.private.id
  fixed_ip   = var.postgresql_fixed_ip

  security_group_ids = [
    openstack_networking_secgroup_v2.management.id,
    openstack_networking_secgroup_v2.postgresql.id,
  ]

  create_floating_ip  = true
  external_network    = openstack_networking_network_v2.external.name
  external_subnet_id  = openstack_networking_subnet_v2.external.id
  data_volume_size_gb = var.postgresql_data_volume_size_gb

  metadata = {
    environment = "lab"
    role        = "postgresql"
    managed_by  = "terraform"
  }

  tags = [
    "lab",
    "postgresql",
    "database",
    "platform",
  ]
}


# Permanent infrastructure entry point for the OKD cluster. It is declared
# explicitly rather than through the generic workload module because this VM
# needs a tiny first-boot DNS override before Ansible owns its configuration.
resource "openstack_networking_port_v2" "okd_lb" {
  name           = "${var.okd_lb_instance_name}-port"
  description    = "Primary OpenShift machine-network port for ${var.okd_lb_instance_name}"
  network_id     = openstack_networking_network_v2.openshift.id
  admin_state_up = true

  security_group_ids = [
    openstack_networking_secgroup_v2.management.id,
    openstack_networking_secgroup_v2.okd_lb.id,
  ]

  fixed_ip {
    subnet_id  = openstack_networking_subnet_v2.openshift.id
    ip_address = var.okd_lb_fixed_ip
  }

  tags = [
    "lab",
    "okd",
    "openshift",
    "load-balancer",
    "dns",
    "platform",
  ]
}

resource "openstack_compute_instance_v2" "okd_lb" {
  depends_on = [openstack_networking_router_interface_v2.openshift]

  name                = var.okd_lb_instance_name
  image_id            = openstack_images_image_v2.ubuntu_2404.id
  flavor_id           = openstack_compute_flavor_v2.small.id
  key_pair            = openstack_compute_keypair_v2.workload.name
  stop_before_destroy = true

  # openshift-subnet advertises okd-lb itself as DNS so future CoreOS nodes
  # resolve private cluster records from first boot. This VM therefore pins
  # its own resolver to public upstreams until Ansible installs the DNS service.
  user_data = <<-CLOUD_CONFIG
    #cloud-config
    write_files:
      - path: /etc/systemd/resolved.conf.d/99-okd-lb-upstream.conf
        permissions: '0644'
        content: |
          [Resolve]
          DNS=1.1.1.1
          FallbackDNS=8.8.8.8
          Domains=~.
    runcmd:
      - systemctl restart systemd-resolved
  CLOUD_CONFIG

  metadata = {
    environment = "lab"
    role        = "okd-load-balancer-dns"
    managed_by  = "terraform"
  }

  tags = [
    "lab",
    "okd",
    "openshift",
    "load-balancer",
    "dns",
    "platform",
  ]

  network {
    port = openstack_networking_port_v2.okd_lb.id
  }
}

resource "openstack_networking_floatingip_v2" "okd_lb" {
  # Neutron can only associate a Floating IP once lab-router has both:
  #   1) its external gateway on public-net, and
  #   2) an interface on openshift-subnet.
  # The port itself can exist before the router interface is ready, so without
  # this explicit dependency a fresh parallel Terraform apply can race and fail
  # with ExternalGatewayForFloatingIPNotFound.
  depends_on = [openstack_networking_router_interface_v2.openshift]

  pool        = openstack_networking_network_v2.external.name
  subnet_id   = openstack_networking_subnet_v2.external.id
  port_id     = openstack_networking_port_v2.okd_lb.id
  description = "Management floating IP for ${var.okd_lb_instance_name}"

  tags = [
    "lab",
    "okd",
    "openshift",
    "management",
  ]
}
