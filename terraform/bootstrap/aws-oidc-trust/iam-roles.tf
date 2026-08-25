data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "aws_dev_foundation_trust" {
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
      values   = ["organization:velteca-org:project:nonproduction:workspace:aws-dev-foundation:run_phase:*"]
    }
  }
}

resource "aws_iam_role" "aws_dev_foundation" {
  name               = "hcp-terraform-aws-dev-foundation"
  assume_role_policy = data.aws_iam_policy_document.aws_dev_foundation_trust.json

  tags = {
    Name           = "hcp-terraform-aws-dev-foundation"
    Owner          = "platform-team"
    Environment    = "dev"
    CostCenter     = "platform-eng"
    Classification = "internal"
    ManagedBy      = "terraform"
  }
}

data "aws_iam_policy_document" "aws_dev_foundation_networking" {
  statement {
    sid    = "VpcNetworkingManagement"
    effect = "Allow"
    actions = [
      "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:ModifyVpcAttribute",
      "ec2:CreateSubnet", "ec2:DeleteSubnet", "ec2:ModifySubnetAttribute",
      "ec2:CreateInternetGateway", "ec2:DeleteInternetGateway", "ec2:AttachInternetGateway", "ec2:DetachInternetGateway",
      "ec2:CreateNatGateway", "ec2:DeleteNatGateway",
      "ec2:AllocateAddress", "ec2:ReleaseAddress", "ec2:AssociateAddress", "ec2:DisassociateAddress",
      "ec2:CreateRouteTable", "ec2:DeleteRouteTable", "ec2:CreateRoute", "ec2:DeleteRoute", "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable",
      "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup", "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress", "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress",
      "ec2:CreateVpcEndpoint", "ec2:DeleteVpcEndpoints", "ec2:ModifyVpcEndpoint",
      "ec2:CreateFlowLogs", "ec2:DeleteFlowLogs",
      "ec2:CreateTags", "ec2:DeleteTags",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "VpcNetworkingRead"
    effect    = "Allow"
    actions   = ["ec2:Describe*"]
    resources = ["*"]
  }

  statement {
    sid    = "FlowLogDelivery"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:PutRetentionPolicy",
      "logs:TagResource",
    ]
    resources = ["arn:aws:logs:us-east-1:${data.aws_caller_identity.current.account_id}:log-group:/aws/vpc-flow-logs/*"]
  }

  statement {
    sid       = "FlowLogRead"
    effect    = "Allow"
    actions   = ["logs:Describe*", "logs:ListTagsForResource"]
    resources = ["*"]
  }

  statement {
    sid    = "FlowLogRole"
    effect = "Allow"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:PutRolePolicy", "iam:DeleteRolePolicy",
      "iam:TagRole", "iam:PassRole",
    ]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/vpc-flow-logs-*"]
  }

  statement {
    sid       = "FlowLogRoleRead"
    effect    = "Allow"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/vpc-flow-logs-*"]
  }
}

resource "aws_iam_role_policy" "aws_dev_foundation_networking" {
  name   = "networking"
  role   = aws_iam_role.aws_dev_foundation.id
  policy = data.aws_iam_policy_document.aws_dev_foundation_networking.json
}

data "aws_iam_policy_document" "aws_dev_foundation_security" {
  statement {
    sid    = "S3AccountPublicAccessBlock"
    effect = "Allow"
    actions = [
      "s3:PutAccountPublicAccessBlock",
      "s3:GetAccountPublicAccessBlock",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "EbsEncryptionByDefault"
    effect = "Allow"
    actions = [
      "ec2:GetEbsEncryptionByDefault",
      "ec2:EnableEbsEncryptionByDefault",
      "ec2:DisableEbsEncryptionByDefault",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "InstanceMetadataDefaults"
    effect = "Allow"
    actions = [
      "ec2:GetInstanceMetadataDefaults",
      "ec2:ModifyInstanceMetadataDefaults",
    ]
    resources = ["*"]
  }

    statement {
    sid    = "EnvironmentKmsKey"
    effect = "Allow"
    actions = [
      "kms:CreateKey",
      "kms:DescribeKey",
      "kms:GetKeyPolicy",
      "kms:PutKeyPolicy",
      "kms:GetKeyRotationStatus",
      "kms:EnableKeyRotation",
      "kms:ScheduleKeyDeletion",
      "kms:CancelKeyDeletion",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:ListResourceTags",
      "kms:CreateAlias",
      "kms:DeleteAlias",
      "kms:UpdateAlias",
      "kms:ListAliases",
    ]
    resources = ["*"]
  }

   statement {
    sid    = "CloudTrailBucketManagement"
    effect = "Allow"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:PutBucketPolicy",
      "s3:DeleteBucketPolicy",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutEncryptionConfiguration",
      "s3:PutBucketVersioning",
      "s3:PutBucketTagging",
    ]
    resources = ["arn:aws:s3:::cloudtrail-logs-${data.aws_caller_identity.current.account_id}"]
  }

  statement {
    sid    = "CloudTrailBucketRead"
    effect = "Allow"
    actions = ["s3:Get*", "s3:List*"]
    resources = ["arn:aws:s3:::cloudtrail-logs-${data.aws_caller_identity.current.account_id}"]
  }

  statement {
    sid    = "CloudTrailManagement"
    effect = "Allow"
    actions = [
      "cloudtrail:CreateTrail",
      "cloudtrail:DeleteTrail",
      "cloudtrail:UpdateTrail",
      "cloudtrail:StartLogging",
      "cloudtrail:StopLogging",
      "cloudtrail:AddTags",
      "cloudtrail:RemoveTags",
    ]
    resources = ["arn:aws:cloudtrail:us-east-1:${data.aws_caller_identity.current.account_id}:trail/dev-account-trail"]
  }

  statement {
    sid    = "CloudTrailRead"
    effect = "Allow"
    actions = [
      "cloudtrail:GetTrail", "cloudtrail:GetTrailStatus", "cloudtrail:DescribeTrails",
      "cloudtrail:ListTags", "cloudtrail:GetEventSelectors",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "aws_dev_foundation_security" {
  name   = "security"
  role   = aws_iam_role.aws_dev_foundation.id
  policy = data.aws_iam_policy_document.aws_dev_foundation_security.json
}