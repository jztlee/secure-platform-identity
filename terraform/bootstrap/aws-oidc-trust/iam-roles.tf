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
      "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:DescribeVpcs", "ec2:ModifyVpcAttribute",
      "ec2:CreateSubnet", "ec2:DeleteSubnet", "ec2:DescribeSubnets", "ec2:ModifySubnetAttribute",
      "ec2:CreateInternetGateway", "ec2:DeleteInternetGateway", "ec2:AttachInternetGateway", "ec2:DetachInternetGateway", "ec2:DescribeInternetGateways",
      "ec2:CreateNatGateway", "ec2:DeleteNatGateway", "ec2:DescribeNatGateways",
      "ec2:AllocateAddress", "ec2:ReleaseAddress", "ec2:DescribeAddresses", "ec2:AssociateAddress", "ec2:DisassociateAddress",
      "ec2:CreateRouteTable", "ec2:DeleteRouteTable", "ec2:CreateRoute", "ec2:DeleteRoute", "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable", "ec2:DescribeRouteTables",
      "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup", "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress", "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress", "ec2:DescribeSecurityGroups",
      "ec2:CreateVpcEndpoint", "ec2:DeleteVpcEndpoints", "ec2:DescribeVpcEndpoints", "ec2:ModifyVpcEndpoint",
      "ec2:CreateFlowLogs", "ec2:DeleteFlowLogs", "ec2:DescribeFlowLogs",
      "ec2:DescribeAvailabilityZones", "ec2:DescribeAccountAttributes",
      "ec2:CreateTags", "ec2:DeleteTags", "ec2:DescribeTags", "ec2:DescribeVpcAttribute",
      "ec2:DescribeAddressesAttribute",

    ]
    resources = ["*"]
  }

  statement {
    sid    = "FlowLogDelivery"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:PutRetentionPolicy",
      "logs:TagResource", "logs:ListTagsForResource",
    ]
    resources = ["arn:aws:logs:us-east-1:${data.aws_caller_identity.current.account_id}:log-group:/aws/vpc-flow-logs/*"]
  }

  statement {
    sid       = "FlowLogDescribe"
    effect    = "Allow"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }

  statement {
    sid    = "FlowLogRole"
    effect = "Allow"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:PutRolePolicy",
      "iam:GetRolePolicy", "iam:DeleteRolePolicy", "iam:TagRole", "iam:PassRole", "iam:ListRolePolicies",
      "iam:ListRoleTags", "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole",
    ]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/vpc-flow-logs-*"]
  }
}

resource "aws_iam_role_policy" "aws_dev_foundation_networking" {
  name   = "networking"
  role   = aws_iam_role.aws_dev_foundation.id
  policy = data.aws_iam_policy_document.aws_dev_foundation_networking.json
}



