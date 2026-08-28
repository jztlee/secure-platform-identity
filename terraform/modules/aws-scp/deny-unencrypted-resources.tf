data "aws_iam_policy_document" "deny_unencrypted_resources" {
  statement {
    sid    = "DenyUnencryptedEBSVolumes"
    effect = "Deny"
    actions = ["ec2:CreateVolume"]
    resources = ["*"]

    condition {
      test     = "Bool"
      variable = "ec2:Encrypted"
      values   = ["false"]
    }
  }

  statement {
    sid    = "DenyUnencryptedS3Uploads"
    effect = "Deny"
    actions = ["s3:PutObject"]
    resources = ["*"]

    condition {
      test     = "Null"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["true"]
    }
  }

  statement {
    sid    = "DenyUnencryptedRDSInstances"
    effect = "Deny"
    actions = ["rds:CreateDBInstance", "rds:CreateDBCluster"]
    resources = ["*"]

    condition {
      test     = "Bool"
      variable = "rds:StorageEncrypted"
      values   = ["false"]
    }
  }
}

resource "aws_organizations_policy" "deny_unencrypted_resources" {
  name        = "deny-unencrypted-resources"
  description = "Denies creating unencrypted EBS volumes, S3 objects without server-side encryption, or unencrypted RDS instances/clusters."
  type        = "SERVICE_CONTROL_POLICY"
  content     = data.aws_iam_policy_document.deny_unencrypted_resources.json

  tags = {
    Name           = "deny-unencrypted-resources"
    Owner          = "platform-team"
    Environment    = "shared"
    CostCenter     = "platform-eng"
    Classification = "internal"
    ManagedBy      = "terraform"
  }
}

resource "aws_organizations_policy_attachment" "deny_unencrypted_resources_dev" {
  policy_id = aws_organizations_policy.deny_unencrypted_resources.id
  target_id = var.dev_account_id
}