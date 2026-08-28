variable "aws_region" {
  description = "AWS region where the public ALB will consume the ACM certificate"
  type        = string
  default     = "eu-south-2"
}

variable "project_name" {
  description = "Project name used for tagging persistent public-ingress resources"
  type        = string
  default     = "private-banking-platform-lab"
}
