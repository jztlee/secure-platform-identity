data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "environment_key" {
  statement {
    sid    = "EnableRootAccountAccess"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }
}

resource "aws_kms_key" "environment" {
  description             = "Customer-managed key for dev environment sensitive workloads"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.environment_key.json

  tags = {
    Name           = "dev-environment-key"
    Owner          = "platform-team"
    Environment    = "dev"
    CostCenter     = "platform-eng"
    Classification = "internal"
    ManagedBy      = "terraform"
  }
}

resource "aws_kms_alias" "environment" {
  name          = "alias/dev-environment"
  target_key_id = aws_kms_key.environment.key_id
}