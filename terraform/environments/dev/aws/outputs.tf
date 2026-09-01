output "vpc_id" {
  description = "ID of the dev VPC."
  value       = module.networking.vpc_id
}

output "private_app_subnet_ids" {
  description = "Private app subnet IDs — EKS node groups will use these in Phase 4."
  value       = module.networking.private_app_subnet_ids
}

output "eks_cluster_name" {
  description = "Name of the dev EKS cluster."
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "API server endpoint for the dev EKS cluster."
  value       = module.eks.cluster_endpoint
}

output "ecr_repository_url" {
  description = "ECR repository URL for the platform-api image."
  value       = module.ecr.repository_url
}