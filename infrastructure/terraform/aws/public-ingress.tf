# Persistent ACM/hosted-zone resources live in aws-global. This daily state
# consumes only their outputs and recreates the cost-bearing ALB/Route53 aliases
# alongside the rest of the ephemeral lab.
data "terraform_remote_state" "aws_global" {
  backend = "s3"

  config = {
    bucket = "realtime-media-analytics-tfstate-156358246560-us-east-1"
    key    = "private-banking-platform-lab/aws-global/terraform.tfstate"
    region = "us-east-1"
  }
}

locals {
  lab_base_domain = data.terraform_remote_state.aws_global.outputs.lab_base_domain
  okd_cluster     = data.terraform_remote_state.aws_global.outputs.okd_cluster_name

  public_service_fqdns = {
    jenkins       = "jenkins.${local.lab_base_domain}"
    openstack     = "cloud.${local.lab_base_domain}"
    openshift_apps = "*.apps.${local.okd_cluster}.${local.lab_base_domain}"
  }
}

resource "aws_security_group" "public_alb" {
  name_prefix            = "${var.project_name}-public-alb-"
  description            = "Public HTTPS entry point for lab web UIs and OKD routes"
  vpc_id                 = data.aws_vpc.default.id
  revoke_rules_on_delete = true

  tags = { Name = "${var.project_name}-public-alb-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "public_alb_http" {
  security_group_id = aws_security_group.public_alb.id
  description       = "HTTP redirect from the explicitly allowed lab client CIDR"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = local.effective_edge_client_cidr
}

resource "aws_vpc_security_group_ingress_rule" "public_alb_https" {
  security_group_id = aws_security_group.public_alb.id
  description       = "HTTPS from the explicitly allowed lab client CIDR"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = local.effective_edge_client_cidr
}

resource "aws_vpc_security_group_egress_rule" "public_alb_to_edge" {
  security_group_id            = aws_security_group.public_alb.id
  referenced_security_group_id = aws_security_group.edge_gateway.id
  description                  = "ALB HTTP traffic to the dedicated edge gateway"
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

resource "aws_lb" "public" {
  name               = "pbp-lab-public"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.public_alb.id]
  subnets            = sort(data.aws_subnets.default.ids)

  drop_invalid_header_fields = true
  idle_timeout               = 300

  lifecycle {
    precondition {
      condition     = length(data.aws_subnets.default.ids) >= 2
      error_message = "The internet-facing ALB requires at least two default-VPC subnets in different Availability Zones."
    }
  }

  tags = { Name = "${var.project_name}-public-alb" }
}

resource "aws_lb_target_group" "edge" {
  name        = "pbp-lab-edge"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = data.aws_vpc.default.id

  deregistration_delay = 10

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/healthz"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = { Name = "${var.project_name}-edge-targets" }
}

resource "aws_lb_target_group_attachment" "edge" {
  target_group_arn = aws_lb_target_group.edge.arn
  target_id        = aws_instance.edge_gateway.id
  port             = 80
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.public.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.public.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = data.terraform_remote_state.aws_global.outputs.lab_edge_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.edge.arn
  }
}

resource "aws_route53_record" "public_services" {
  for_each = local.public_service_fqdns

  zone_id = data.terraform_remote_state.aws_global.outputs.public_dns_zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = aws_lb.public.dns_name
    zone_id                = aws_lb.public.zone_id
    evaluate_target_health = true
  }
}
