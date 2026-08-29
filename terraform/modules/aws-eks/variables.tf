variable "vpc_id" {
  description = "VPC ID the cluster and its security groups live in."
  type        = string
}

variable "private_app_subnet_ids" {
  description = "Private app subnet IDs for the cluster's ENIs and worker nodes."
  type        = list(string)
}

variable "tags" {
  description = "Common resource tags."
  type        = map(string)
}

variable "allowed_cidrs" {
  description = "CIDR blocks allowed to reach the EKS API endpoint."
  type        = list(string)
}