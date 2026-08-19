output "hcp_terraform_oidc_provider_arn" {
  description = "The ARN of the IAM OIDC provider that trusts HCP Terraform. Referenced by workspace-specific IAM roles created in later phases."
  value       = aws_iam_openid_connect_provider.hcp_terraform.arn
}

output "aws_dev_foundation_role_arn" {
  description = "The ARN of the IAM role aws-dev-foundation assumes via OIDC."
  value       = aws_iam_role.aws_dev_foundation.arn
}