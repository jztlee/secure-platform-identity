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