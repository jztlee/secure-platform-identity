output "vpc_id" {
  description = "ID of the dev VPC."
  value       = module.networking.vpc_id
}

output "private_app_subnet_ids" {
  description = "Private app subnet IDs — EKS node groups will use these in Phase 4."
  value       = module.networking.private_app_subnet_ids
}