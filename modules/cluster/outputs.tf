output "cluster_name" {
  value       = module.eks.cluster_name
  description = "Name of the EKS cluster"
}

output "cluster_arn" {
  value       = module.eks.cluster_arn
  description = "ARN of the EKS cluster"
}

output "cluster_endpoint" {
  value       = module.eks.cluster_endpoint
  description = "Endpoint of the EKS cluster"
}

output "cluster_certificate_authority" {
  value       = module.eks.cluster_certificate_authority_data
  description = "Certificate authority of the EKS cluster"
}