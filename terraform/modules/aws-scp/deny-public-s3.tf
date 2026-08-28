data "aws_iam_policy_document" "deny_public_s3" {
  statement {
    sid    = "DenyPublicReadWriteACL"
    effect = "Deny"
    actions = [
      "s3:PutBucketAcl",
      "s3:PutObjectAcl",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["public-read", "public-read-write"]
    }
  }

  statement {
    sid    = "DenyDisablingAccountPublicAccessBlock"
    effect = "Deny"
    actions = [
      "s3:PutAccountPublicAccessBlock",
      "s3:DeleteAccountPublicAccessBlock",
    ]
    resources = ["*"]
  }
}

resource "aws_organizations_policy" "deny_public_s3" {
  name        = "deny-public-s3"
  description = "Prevents any principal, including admins, from granting public S3 ACLs or disabling the account-level Block Public Access setting."
  type        = "SERVICE_CONTROL_POLICY"
  content     = data.aws_iam_policy_document.deny_public_s3.json

  tags = {
    Name           = "deny-public-s3"
    Owner          = "platform-team"
    Environment    = "shared"
    CostCenter     = "platform-eng"
    Classification = "internal"
    ManagedBy      = "terraform"
  }
}

resource "aws_organizations_policy_attachment" "deny_public_s3_dev" {
  policy_id = aws_organizations_policy.deny_public_s3.id
  target_id = var.dev_account_id
}