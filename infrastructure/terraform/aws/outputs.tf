output "instance_id" {
  description = "EC2 lab instance ID"
  value       = aws_instance.lab.id
}

output "instance_type" {
  description = "EC2 lab instance type"
  value       = aws_instance.lab.instance_type
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
