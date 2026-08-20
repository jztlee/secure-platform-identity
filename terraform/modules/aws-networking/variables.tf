variable "environment" {
  description = "Environment name (e.g. dev, staging, prod). Used in resource names and tags."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones to spread subnets accross. Must have at least 2."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least 2 availability zones are required for a multi-AZ VPC."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets, one per Availability Zone, in the same order as availability_zones."
  type        = list(string)
}

variable "private_app_subnet_cidrs" {
  description = "CIDR blocks for private application subnets (e.g. EKS nodes), one per Availability Zone"
  type        = list(string)
}

variable "private_data_subnet_cidrs" {
  description = "CIDR blocks for private data subnets (e.g. databases), one per Availability Zone"
  type        = list(string)
}

variable "tags" {
  description = "Common tags applied to every resource this module creates."
  type        = map(string)
  default     = {}
}
