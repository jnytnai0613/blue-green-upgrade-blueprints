output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "IDs of the Private Subnets"
  value       = module.vpc.private_subnets
}

output "aws_route53_zone" {
  description = "The new Route53 Zone"
  value       = aws_route53_zone.sub.name
}

output "pod_dynamodb_role_arn" {
  description = "IAM Role Arn of Pod to read dynamodb"
  value       = aws_iam_role.read_dynamodb.arn
}

output "pod_lb_role_arn" {
  description = "IAM Role Arn of Pod to Load Balancer Controller"
  value       = aws_iam_role.alb_ingress_controller.arn
}

output "pod_external_dns_role_arn" {
  description = "IAM Role Arn of Pod to External DNS"
  value       = aws_iam_role.external_dns.arn
}