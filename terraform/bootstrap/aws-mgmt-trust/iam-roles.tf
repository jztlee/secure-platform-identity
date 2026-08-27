data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "aws_mgmt_scp_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.hcp_terraform.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "app.terraform.io:aud"
      values   = ["aws.workload.identity"]
    }

    condition {
      test     = "StringLike"
      variable = "app.terraform.io:sub"
      values   = ["organization:velteca-org:project:shared-platform:workspace:aws-mgmt-scp:run_phase:*"]
    }
  }
}

resource "aws_iam_role" "aws_mgmt_scp" {
  name               = "hcp-terraform-aws-mgmt-scp"
  assume_role_policy = data.aws_iam_policy_document.aws_mgmt_scp_trust.json

  tags = {
    Name           = "hcp-terraform-aws-mgmt-scp"
    Owner          = "platform-team"
    Environment    = "shared"
    CostCenter     = "platform-eng"
    Classification = "internal"
    ManagedBy      = "terraform"
  }
}

data "aws_iam_policy_document" "aws_mgmt_scp_policy" {
  statement {
    sid    = "SCPManagement"
    effect = "Allow"
    actions = [
      "organizations:CreatePolicy",
      "organizations:UpdatePolicy",
      "organizations:DeletePolicy",
      "organizations:AttachPolicy",
      "organizations:DetachPolicy",
      "organizations:TagResource",
      "organizations:UntagResource",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "SCPRead"
    effect = "Allow"
    actions = [
      "organizations:DescribePolicy",
      "organizations:ListPolicies",
      "organizations:ListPoliciesForTarget",
      "organizations:ListTargetsForPolicy",
      "organizations:ListTagsForResource",
      "organizations:DescribeOrganization",
      "organizations:ListRoots",
      "organizations:ListAccounts",
      "organizations:ListAccountsForParent",
      "organizations:ListOrganizationalUnitsForParent",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "aws_mgmt_scp" {
  name   = "scp-management"
  role   = aws_iam_role.aws_mgmt_scp.id
  policy = data.aws_iam_policy_document.aws_mgmt_scp_policy.json
}