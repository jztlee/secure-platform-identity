data "tls_certificate" "hcp_terraform" {
  url = "https://app.terraform.io"
}

resource "aws_iam_openid_connect_provider" "hcp_terraform" {
  url             = "https://app.terraform.io"
  client_id_list  = ["aws.workload.identity"]
  thumbprint_list = [data.tls_certificate.hcp_terraform.certificates[0].sha1_fingerprint]

  tags = {
    Name           = "hcp-terraform-oidc"
    Owner          = "platform-velteca"
    Environment    = "shared"
    CostCenter     = "platform-eng"
    Classification = "internal"
    ManagedBy      = "terraform"
  }
}

output "hcp_terraform_oidc_provider_arn" {
  description = "The ARN of the IAM OIDC provider that trusts HCP Terraform. Referenced by workspace-specific IAM roles created in later phases."
  value       = aws_iam_openid_connect_provider.hcp_terraform.arn
}