data "tls_certificate" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github_actions.certificates[0].sha1_fingerprint]
}

data "aws_iam_policy_document" "github_actions_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:jztlee/secure-platform-identity:*"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "github-actions-platform-api"
  assume_role_policy = data.aws_iam_policy_document.github_actions_trust.json

  tags = {
    Name           = "github-actions-platform-api"
    Owner          = "platform-team"
    Environment    = "dev"
    CostCenter     = "platform-eng"
    Classification = "internal"
    ManagedBy      = "terraform"
  }
}