data "aws_iam_policy_document" "protect_audit_services" {
  statement {
    sid    = "DenyCloudTrailDisable"
    effect = "Deny"
    actions = [
      "cloudtrail:StopLogging",
      "cloudtrail:DeleteTrail",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DenyConfigDisable"
    effect = "Deny"
    actions = [
      "config:DeleteConfigurationRecorder",
      "config:StopConfigurationRecorder",
      "config:DeleteDeliveryChannel",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DenyGuardDutyDisable"
    effect = "Deny"
    actions = [
      "guardduty:DeleteDetector",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DenySecurityHubDisable"
    effect = "Deny"
    actions = [
      "securityhub:DisableSecurityHub",
    ]
    resources = ["*"]
  }
}

resource "aws_organizations_policy" "protect_audit_services" {
  name        = "protect-audit-services"
  description = "Prevents any principal, including admins, from disabling CloudTrail, Config, GuardDuty, or Security Hub."
  type        = "SERVICE_CONTROL_POLICY"
  content     = data.aws_iam_policy_document.protect_audit_services.json

  tags = {
    Name           = "protect-audit-services"
    Owner          = "platform-team"
    Environment    = "shared"
    CostCenter     = "platform-eng"
    Classification = "internal"
    ManagedBy      = "terraform"
  }
}

resource "aws_organizations_policy_attachment" "protect_audit_services_dev" {
  policy_id = aws_organizations_policy.protect_audit_services.id
  target_id = var.dev_account_id
}