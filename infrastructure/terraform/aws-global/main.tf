locals {
  cluster_config = yamldecode(file("${path.module}/../../../platform/openshift/cluster-config.yml"))

  public_dns_zone = local.cluster_config.lab_public_dns_zone
  lab_base_domain = local.cluster_config.okd_base_domain
  okd_cluster     = local.cluster_config.okd_cluster_name

  edge_certificate_names = [
    "*.${local.lab_base_domain}",
    "*.apps.${local.okd_cluster}.${local.lab_base_domain}",
  ]
}

data "aws_route53_zone" "public" {
  name         = local.public_dns_zone
  private_zone = false
}

# This certificate intentionally lives in a separate persistent Terraform
# state. The daily lab can be destroyed/rebuilt without repeatedly requesting
# new public certificates or deleting the DNS validation records ACM needs for
# managed renewal.
resource "aws_acm_certificate" "lab_edge" {
  domain_name               = local.edge_certificate_names[0]
  subject_alternative_names = slice(local.edge_certificate_names, 1, length(local.edge_certificate_names))
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "acm_validation" {
  for_each = {
    for option in aws_acm_certificate.lab_edge.domain_validation_options :
    option.domain_name => {
      name   = option.resource_record_name
      record = option.resource_record_value
      type   = option.resource_record_type
    }
  }

  zone_id = data.aws_route53_zone.public.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "lab_edge" {
  certificate_arn = aws_acm_certificate.lab_edge.arn
  validation_record_fqdns = [
    for record in aws_route53_record.acm_validation : record.fqdn
  ]
}
