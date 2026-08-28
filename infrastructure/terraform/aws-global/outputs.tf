output "public_dns_zone_id" {
  description = "Existing Route53 public hosted-zone ID used by the lab"
  value       = data.aws_route53_zone.public.zone_id
}

output "public_dns_zone_name" {
  description = "Existing Route53 public hosted-zone name used by the lab"
  value       = local.public_dns_zone
}

output "lab_base_domain" {
  description = "Stable lab DNS suffix shared by Jenkins, Horizon and OKD"
  value       = local.lab_base_domain
}

output "okd_cluster_name" {
  description = "OKD cluster name used to build the apps wildcard"
  value       = local.okd_cluster
}

output "lab_edge_certificate_arn" {
  description = "Persistent ACM certificate consumed by the ephemeral public ALB"
  value       = aws_acm_certificate_validation.lab_edge.certificate_arn
}

output "lab_edge_certificate_names" {
  description = "DNS names covered by the public edge certificate"
  value       = local.edge_certificate_names
}
