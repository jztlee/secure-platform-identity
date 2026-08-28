locals {
  permission_sets = {
    platform-admin = {
      description         = "Full platform administration - Terraform, AWS, cluster admin"
      managed_policy_arn  = "arn:aws:iam::aws:policy/AdministratorAccess"
      session_duration    = "PT4H"
    }
    developer = {
      description         = "Broad application-development access, short of IAM/org management"
      managed_policy_arn  = "arn:aws:iam::aws:policy/PowerUserAccess"
      session_duration    = "PT8H"
    }
    security-auditor = {
      description         = "Read-only access scoped for security auditing"
      managed_policy_arn  = "arn:aws:iam::aws:policy/SecurityAudit"
      session_duration    = "PT8H"
    }
    read-only = {
      description         = "General read-only access across the account"
      managed_policy_arn  = "arn:aws:iam::aws:policy/ReadOnlyAccess"
      session_duration    = "PT8H"
    }
  }
}

data "aws_ssoadmin_instances" "main" {}

resource "aws_ssoadmin_permission_set" "this" {
  for_each = local.permission_sets

  instance_arn     = tolist(data.aws_ssoadmin_instances.main.arns)[0]
  name             = each.key
  description      = each.value.description
  session_duration = each.value.session_duration

  tags = {
    Name           = each.key
    Owner          = "platform-team"
    Environment    = "shared"
    CostCenter     = "platform-eng"
    Classification = "internal"
    ManagedBy      = "terraform"
  }
}

resource "aws_ssoadmin_managed_policy_attachment" "this" {
  for_each = local.permission_sets

  instance_arn       = tolist(data.aws_ssoadmin_instances.main.arns)[0]
  managed_policy_arn = each.value.managed_policy_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.key].arn
}

data "aws_identitystore_group" "this" {
  for_each = local.permission_sets

  identity_store_id = tolist(data.aws_ssoadmin_instances.main.identity_store_ids)[0]

  alternate_identifier {
    unique_attribute {
      attribute_path  = "DisplayName"
      attribute_value = each.key
    }
  }
}

resource "aws_ssoadmin_account_assignment" "dev" {
  for_each = local.permission_sets

  instance_arn       = tolist(data.aws_ssoadmin_instances.main.arns)[0]
  permission_set_arn = aws_ssoadmin_permission_set.this[each.key].arn

  principal_id   = data.aws_identitystore_group.this[each.key].id
  principal_type = "GROUP"

  target_id   = var.dev_account_id
  target_type = "AWS_ACCOUNT"
}