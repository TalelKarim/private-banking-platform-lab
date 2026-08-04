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
  value       = aws_ebs_volume.lab_data.id
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