output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets, in the same order as availability_zones."
  value       = aws_subnet.public[*].id
}

output "private_app_subnet_ids" {
  description = "IDs of the private application subnets (e.g. for EKS nodes), in the same order as availability_zones."
  value       = aws_subnet.private_app[*].id
}

output "private_data_subnet_ids" {
  description = "IDs of the private data subnets, in the same order as availability_zones."
  value       = aws_subnet.private_data[*].id
}

output "nat_gateway_ids" {
  description = "IDs of the NAT Gateways, one per Availability Zone."
  value       = aws_nat_gateway.main[*].id
}