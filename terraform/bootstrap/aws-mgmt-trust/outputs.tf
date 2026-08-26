output "hcp_terraform_oidc_provider_arn" {
  description = "The ARN of the IAM OIDC provider that trusts HCP Terraform in the management account."
  value       = aws_iam_openid_connect_provider.hcp_terraform.arn
}

output "aws_mgmt_scp_role_arn" {
  description = "The ARN of the IAM role aws-mgmt-scp assumes via OIDC."
  value       = aws_iam_role.aws_mgmt_scp.arn
}