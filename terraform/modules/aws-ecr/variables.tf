variable "repository_name" {
  description = "Name of the ECR repository."
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN used to encrypt images at rest."
  type        = string
}

variable "tags" {
  description = "Common resource tags."
  type        = map(string)
}