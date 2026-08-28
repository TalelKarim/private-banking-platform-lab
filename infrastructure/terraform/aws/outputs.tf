output "instance_id" {
  description = "EC2 lab instance ID"
  value       = aws_instance.lab.id
}

output "instance_type" {
  description = "EC2 lab instance type"
  value       = aws_instance.lab.instance_type
}

output "lab_host_capacity" {
  description = "Declared durable capacity for the OpenStack/OpenShift lab host"
  value = {
    instance_type          = var.instance_type
    root_volume_size_gib   = var.root_volume_size
    data_volume_size_gib   = var.data_volume_size
    cinder_volume_size_gib = var.cinder_volume_size
  }
}

output "availability_zone" {
  description = "Availability Zone hosting the EC2 instance"
  value       = aws_instance.lab.availability_zone
}

output "public_ip" {
  description = "Current public IPv4 address"
  value       = aws_instance.lab.public_ip
}

output "private_ip" {
  description = "Private IPv4 address"
  value       = aws_instance.lab.private_ip
}

output "ubuntu_ami_id" {
  description = "Ubuntu 24.04 AMI selected through SSM"
  value       = data.aws_ssm_parameter.ubuntu_2404_ami.value
  sensitive   = true
}

output "data_volume_id" {
  description = "Persistent data EBS volume"
  value       = local.use_golden_ami ? null : aws_ebs_volume.lab_data[0].id
}


output "cinder_volume_id" {
  description = "Dedicated Cinder LVM EBS volume"
  value       = local.use_golden_ami ? null : aws_ebs_volume.cinder[0].id
}

output "spot_instance_request_id" {
  description = "Persistent Spot request ID"
  value       = aws_instance.lab.spot_instance_request_id
}

output "ssh_private_key_path" {
  description = "Local private SSH key path"
  value       = local_sensitive_file.ssh_private_key.filename
}

output "ssh_command" {
  description = "Direct SSH command from the Mac"
  value       = "ssh -i '${local_sensitive_file.ssh_private_key.filename}' ubuntu@${aws_instance.lab.public_ip}"
}

output "ec2_instance_connect_command" {
  description = "Connection through EC2 Instance Connect CLI"
  value       = "aws ec2-instance-connect ssh --instance-id ${aws_instance.lab.id} --connection-type direct --region ${var.aws_region}"
}

output "ssm_command" {
  description = "Connection through AWS Systems Manager"
  value       = "aws ssm start-session --target ${aws_instance.lab.id} --region ${var.aws_region}"
}

output "bootstrap_log_command" {
  description = "Command to wait for cloud-init and inspect the bootstrap log"
  value       = "sudo cloud-init status --wait && sudo tail -n 200 /var/log/private-banking-lab-bootstrap.log"
}

output "aws_region" {
  description = "AWS region used by the lab"
  value       = var.aws_region
}

output "effective_ami_id" {
  description = "AMI currently selected for the OpenStack host"
  value       = local.use_golden_ami ? var.golden_ami_id : data.aws_ssm_parameter.ubuntu_2404_ami.value
  sensitive   = true
}

output "golden_ami_mode" {
  description = "Whether the host is launched directly from a baked OpenStack AMI"
  value       = local.use_golden_ami
}


output "configured_openstack_host_private_ip" {
  description = "Stable private IPv4 that Golden-AMI launches must reuse"
  value       = var.openstack_host_private_ip
}

output "ops_runner_instance_id" {
  description = "EC2 instance ID of the Terraform and Ansible administration runner"
  value       = aws_instance.ops_runner.id
}

output "ops_runner_instance_type" {
  description = "EC2 instance type of the administration runner"
  value       = aws_instance.ops_runner.instance_type
}

output "ops_runner_private_ip" {
  description = "Private IPv4 address of the administration runner"
  value       = aws_instance.ops_runner.private_ip
}

output "ops_runner_public_ip" {
  description = "Public IPv4 address of the administration runner"
  value       = aws_instance.ops_runner.public_ip
}

output "ops_runner_ssh_command" {
  description = "Direct SSH command for the administration runner"
  value       = "ssh -i '${local_sensitive_file.ssh_private_key.filename}' ubuntu@${aws_instance.ops_runner.public_ip}"
}

output "ops_runner_ec2_instance_connect_command" {
  description = "EC2 Instance Connect command for the administration runner"
  value       = "aws ec2-instance-connect ssh --instance-id ${aws_instance.ops_runner.id} --connection-type direct --region ${var.aws_region}"
}

output "ops_runner_ssm_command" {
  description = "SSM Session Manager command for the administration runner"
  value       = "aws ssm start-session --target ${aws_instance.ops_runner.id} --region ${var.aws_region}"
}

output "ops_runner_bootstrap_log_command" {
  description = "Command to wait for the administration runner bootstrap and inspect its log"
  value       = "sudo cloud-init status --wait && sudo tail -n 200 /var/log/private-banking-lab-ops-runner-bootstrap.log"
}

output "ops_runner_tfc_agent_status_command" {
  description = "Command to inspect the HCP Terraform Agent service"
  value       = "sudo systemctl status tfc-agent --no-pager --full"
}

output "ops_runner_tfc_agent_logs_command" {
  description = "Command to follow HCP Terraform Agent logs"
  value       = "sudo journalctl -u tfc-agent -f"
}

output "ops_runner_tfc_agent_token_parameter_name" {
  description = "SSM Parameter Store path from which the ops-runner reads its HCP Terraform agent-pool token"
  value       = var.tfc_agent_token_ssm_parameter_name
}

output "openstack_external_route" {
  description = "VPC route that sends the OpenStack provider network to the lab-host ENI"
  value = {
    route_table_id         = local.selected_route_table_id
    destination_cidr_block = aws_route.openstack_external_via_lab_host.destination_cidr_block
    network_interface_id   = aws_instance.lab.primary_network_interface_id
  }
}

output "ops_runner_workload_ssh_private_key_path" {
  description = "Private key path used by Ansible on the ops runner for OpenStack workload VMs"
  value       = "/home/ubuntu/.ssh/private-banking-openstack-workloads"
}

output "ops_runner_workload_ssh_key_parameter_name" {
  description = "SSM SecureString path read by the ops runner for the OpenStack workload private key"
  value       = var.workload_ssh_private_key_ssm_parameter_name
}

output "postgresql_app_password_parameter_name" {
  description = "SSM SecureString path used by Ansible for the PostgreSQL portfolio application password"
  value       = var.postgresql_app_password_ssm_parameter_name
}

output "edge_gateway_instance_id" {
  description = "EC2 instance ID of the HTTP/HTTPS edge gateway"
  value       = aws_instance.edge_gateway.id
}

output "edge_gateway_private_ip" {
  description = "Stable private IPv4 address of the edge gateway"
  value       = aws_instance.edge_gateway.private_ip
}

output "edge_gateway_public_ip" {
  description = "Elastic IPv4 address of the edge gateway"
  value       = aws_eip.edge_gateway.public_ip
}

output "edge_gateway_http_url" {
  description = "Direct edge EIP retained for administration/debug only; public web access uses the ALB"
  value       = "http://${aws_eip.edge_gateway.public_ip}"
}

output "edge_gateway_ec2_instance_connect_command" {
  description = "EC2 Instance Connect command for the edge gateway"
  value       = "aws ec2-instance-connect ssh --instance-id ${aws_instance.edge_gateway.id} --connection-type direct --region ${var.aws_region}"
}

output "edge_gateway_ssm_command" {
  description = "SSM command for the edge gateway"
  value       = "aws ssm start-session --target ${aws_instance.edge_gateway.id} --region ${var.aws_region}"
}

output "edge_gateway_bootstrap_log_command" {
  description = "Inspect edge cloud-init"
  value       = "sudo cloud-init status --wait && sudo tail -n 200 /var/log/private-banking-lab-edge-gateway-bootstrap.log"
}

output "public_alb_dns_name" {
  description = "AWS DNS name of the ephemeral public Application Load Balancer"
  value       = aws_lb.public.dns_name
}

output "public_alb_arn" {
  description = "ARN of the ephemeral public Application Load Balancer"
  value       = aws_lb.public.arn
}

output "public_alb_target_group_arn" {
  description = "Target group ARN used to validate edge-gateway health"
  value       = aws_lb_target_group.edge.arn
}

output "public_lab_urls" {
  description = "Browser-facing HTTPS endpoints published through Route53 -> ALB -> edge-gateway"
  value = {
    jenkins          = "https://${local.public_service_fqdns.jenkins}"
    openstack        = "https://${local.public_service_fqdns.openstack}"
    openshift_console = "https://console-openshift-console.apps.${local.okd_cluster}.${local.lab_base_domain}"
    openshift_oauth   = "https://oauth-openshift.apps.${local.okd_cluster}.${local.lab_base_domain}"
  }
}
