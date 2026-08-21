resource "tls_private_key" "lab" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "ssh_private_key" {
  content = tls_private_key.lab.private_key_pem

  filename             = "${path.root}/.keys/${var.project_name}.pem"
  file_permission      = "0600"
  directory_permission = "0700"
}

resource "local_file" "ssh_public_key" {
  content = trimspace(tls_private_key.lab.public_key_openssh)

  filename             = "${path.root}/.keys/${var.project_name}.pub"
  file_permission      = "0644"
  directory_permission = "0700"
}

resource "aws_key_pair" "lab" {
  key_name   = "${var.project_name}-key"
  public_key = trimspace(tls_private_key.lab.public_key_openssh)

  tags = {
    Name = "${var.project_name}-key"
  }
}

# Terraform already owns this EC2 SSH key. The SecureString copy lets the
# ops-runner retrieve it only during Ansible runs against AWS-side utility VMs.
resource "aws_ssm_parameter" "lab_ssh_private_key" {
  name        = var.lab_ssh_private_key_ssm_parameter_name
  description = "Private SSH key for Terraform-managed AWS lab instances"
  type        = "SecureString"
  value       = tls_private_key.lab.private_key_pem
  tags        = { Name = "${var.project_name}-lab-ssh-private-key" }
}
