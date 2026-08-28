# Terraform module guide

Module guide and HCP Terraform workspace map (spec §5, §17). Reflects what's
actually built as of Phase 3 — not a target-state description.

## Workspace map

| Workspace | Project | Workflow | Applies |
|---|---|---|---|
| `bootstrap-aws-trust` | `bootstrap` | CLI-driven | `terraform/bootstrap/aws-oidc-trust/` |
| `bootstrap-mgmt-trust` | `bootstrap` | CLI-driven | `terraform/bootstrap/aws-mgmt-trust/` |
| `aws-dev-foundation` | `nonproduction` | VCS-driven | `terraform/environments/dev/aws/` |
| `aws-mgmt-scp` | `shared-platform` | VCS-driven | `terraform/environments/mgmt/aws/` |

**Why two bootstrap workspaces, not one:** OIDC trust is account-scoped —
each AWS account (`dev`, `mgmt`) needs its own IAM OIDC provider and its own
IAM role, so each got its own bootstrap directory and workspace. Both are
CLI-driven on purpose: they grant AWS permissions to the automated
workspaces below them, and permission-granting changes go through a human
with a separately-authenticated, MFA-gated session — never the same
automated pipeline that provisions routine infrastructure. See
`docs/adr/` for the full reasoning.

**Why `aws-mgmt-scp` lives in a `shared-platform` project, not
`nonproduction`:** its trust policy's `sub` condition is scoped to that
exact project name — SCPs and Identity Center permission sets are org-wide
concerns, not tied to one environment, so they don't belong under the same
project as dev-only infrastructure.

## Modules

### `aws-networking`
VPC, public/private-app/private-data subnets across 2 AZs, NAT gateways,
Internet Gateway, VPC Flow Logs to CloudWatch, VPC endpoints (S3 gateway;
ECR api/dkr, STS, Secrets Manager, CloudWatch Logs interface endpoints).

- **Inputs:** `environment`, `vpc_cidr`, `availability_zones`, subnet CIDR
  lists, `tags`
- **Outputs:** `vpc_id`, `private_app_subnet_ids`
- **Applied by:** `aws-dev-foundation`

### `aws-security`
Account-level hardening (S3 Block Public Access, EBS encryption-by-default,
IMDSv2-required) plus the encryption/audit foundation: a customer-managed
KMS key, CloudTrail (multi-region trail + KMS-encrypted, versioned S3
bucket), AWS Config (service-linked role + KMS-encrypted S3 bucket),
GuardDuty, Security Hub, Inspector (ECR + EC2), and IAM Access Analyzer
(account type).

- **Inputs:** none (account/region-scoped resources; no environment
  parameterization needed since only `dev` exists)
- **Applied by:** `aws-dev-foundation`

### `aws-scp`
One Service Control Policy (`protect-audit-services`) denying the quietest
disable actions against CloudTrail, Config, GuardDuty, and Security Hub —
`StopLogging`/`DeleteTrail`, recorder/channel deletion, `DeleteDetector`,
`DisableSecurityHub`. Attached directly to the dev account.

- **Inputs:** `dev_account_id` (set as an HCP Terraform workspace variable,
  never committed — see the placeholder guardrail in spec §17)
- **Applied by:** `aws-mgmt-scp`
- **Deliberate gap:** doesn't block `UpdateTrail`/`UpdateDetector`, since
  `aws-dev-foundation` legitimately needs those for routine config changes.
  Stops outright disabling, not every tampering vector.

### `aws-identity-center`
Four IAM Identity Center permission sets (`platform-admin` →
`AdministratorAccess`, `developer` → `PowerUserAccess`, `security-auditor`
→ `SecurityAudit`, `read-only` → `ReadOnlyAccess`), each attached to a
managed policy and assigned to its matching Okta-synced group on the dev
account.

- **Inputs:** `dev_account_id`
- **Applied by:** `aws-mgmt-scp`
- **Depends on:** the Okta groups already existing and SCIM-synced into
  Identity Center — `aws_identitystore_group` data sources look them up by
  name at plan time, so the permission-set/group mapping fails to resolve
  if a group doesn't exist yet.

## Bootstrap directories (not modules — applied once, by hand)

### `bootstrap/aws-oidc-trust`
Creates the dev account's OIDC provider trusting HCP Terraform, and the
`hcp-terraform-aws-dev-foundation` IAM role `aws-dev-foundation` assumes.
Applied via a temporary MFA-gated operator credential
(`bootstrap-operator`), since nothing else has AWS access yet.

### `bootstrap/aws-mgmt-trust`
Same shape, for the management account: OIDC provider + the
`hcp-terraform-aws-mgmt-scp` role. Applied via its own MFA-gated operator
(`mgmt-bootstrap-operator`) — a separate credential per account, not reused
across accounts.

## Known tradeoffs

See `docs/acceptance-checklist.md` → "Known tradeoffs to revisit" for the
specific IAM wildcard-read-verb decisions (networking, IAM roles, the
CloudTrail/Config S3 buckets) and their reasoning.
