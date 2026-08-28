data "aws_iam_policy_document" "deny_unapproved_regions" {
  statement {
    sid    = "GRREGIONDENY"
    effect = "Deny"

    not_actions = [
      "a4b:*", "access-analyzer:*", "account:*", "acm:*", "activate:*", "artifact:*",
      "aws-marketplace-management:*", "aws-marketplace:*", "aws-portal:*", "billing:*",
      "billingconductor:*", "budgets:*", "ce:*", "chatbot:*", "chime:*", "cloudfront:*",
      "cloudtrail:LookupEvents", "compute-optimizer:*", "config:*", "consoleapp:*",
      "consolidatedbilling:*", "cur:*", "datapipeline:GetAccountLimits", "devicefarm:*",
      "directconnect:*", "ec2:DescribeRegions", "ec2:DescribeTransitGateways",
      "ec2:DescribeVpnGateways", "ecr-public:*", "fms:*", "freetier:*",
      "globalaccelerator:*", "health:*", "iam:*", "importexport:*", "invoicing:*", "iq:*",
      "kms:*", "license-manager:ListReceivedLicenses", "lightsail:Get*",
      "mobileanalytics:*", "networkmanager:*", "notifications-contacts:*",
      "notifications:*", "organizations:*", "payments:*", "pricing:*",
      "quicksight:DescribeAccountSubscription", "resource-explorer-2:*",
      "route53-recovery-cluster:*", "route53-recovery-control-config:*",
      "route53-recovery-readiness:*", "route53:*", "route53domains:*",
      "s3:CreateMultiRegionAccessPoint", "s3:DeleteMultiRegionAccessPoint",
      "s3:DescribeMultiRegionAccessPointOperation", "s3:GetAccountPublicAccessBlock",
      "s3:GetBucketLocation", "s3:GetBucketPolicyStatus", "s3:GetBucketPublicAccessBlock",
      "s3:GetMultiRegionAccessPoint", "s3:GetMultiRegionAccessPointPolicy",
      "s3:GetMultiRegionAccessPointPolicyStatus", "s3:GetStorageLensConfiguration",
      "s3:GetStorageLensDashboard", "s3:ListAllMyBuckets", "s3:ListMultiRegionAccessPoints",
      "s3:ListStorageLensConfigurations", "s3:PutAccountPublicAccessBlock",
      "s3:PutMultiRegionAccessPointPolicy", "savingsplans:*", "shield:*", "sso:*", "sts:*",
      "support:*", "supportapp:*", "supportplans:*", "sustainability:*",
      "tag:GetResources", "tax:*", "trustedadvisor:*",
      "vendor-insights:ListEntitledSecurityProfiles", "waf-regional:*", "waf:*", "wafv2:*",
    ]

    resources = ["*"]

    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestedRegion"
      values   = ["us-east-1"]
    }
  }
}

resource "aws_organizations_policy" "deny_unapproved_regions" {
  name        = "deny-unapproved-regions"
  description = "Denies actions outside us-east-1, except for AWS's own documented list of inherently global services (IAM, Organizations, STS, Route 53, CloudFront, KMS, etc.)."
  type        = "SERVICE_CONTROL_POLICY"
  content     = data.aws_iam_policy_document.deny_unapproved_regions.json

  tags = {
    Name           = "deny-unapproved-regions"
    Owner          = "platform-team"
    Environment    = "shared"
    CostCenter     = "platform-eng"
    Classification = "internal"
    ManagedBy      = "terraform"
  }
}

resource "aws_organizations_policy_attachment" "deny_unapproved_regions_dev" {
  policy_id = aws_organizations_policy.deny_unapproved_regions.id
  target_id = var.dev_account_id
}