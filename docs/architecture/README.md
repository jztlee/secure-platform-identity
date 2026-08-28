# Architecture

Expands on the flowchart in spec §3. Two AWS accounts exist as of Phase 3 —
`secure-platform-dev` (workload account) and `secure-platform-mgmt`
(AWS Organizations management account) — reflecting the actual, built
state, not the full seven-account target model (documented separately, not
provisioned; see spec §2).

## Account structure

```
AWS Organization (secure-platform-mgmt is the management account)
├── secure-platform-mgmt (204141434145) — management account
│   ├── AWS Organizations — org root, SCPs attached here
│   └── IAM Identity Center — enabled here, federates to every member account
└── secure-platform-dev (133857166442) — workload account
    ├── VPC, EKS (Phase 4+), ECR (Phase 4+)
    ├── CloudTrail, Config, GuardDuty, Security Hub, Inspector, Access Analyzer
    └── The SCP attached from secure-platform-mgmt constrains everything here
```

**Why two accounts instead of one:** two AWS-platform mechanisms in this
project — SCPs and IAM Identity Center — are *structurally* impossible to
run from a member account. AWS's Organizations API for creating/attaching
policies, and Identity Center's instance itself, only exist at the
management-account level. This isn't a design preference; it's a hard
platform constraint, and it's what makes the guardrail meaningful: a
compromised dev-account credential, even with full admin IAM permissions
*inside* dev, structurally cannot touch the SCP protecting it.

## Identity flow

```
Human operator
  → Okta (SSO + phishing-resistant MFA, authoritative directory)
  → SAML → IAM Identity Center (secure-platform-mgmt)
  → SCIM → groups/users provisioned into Identity Center automatically
  → Permission set + account assignment → federated access into secure-platform-dev
```

Four Okta groups (`platform-admin`, `developer`, `security-auditor`,
`read-only`) map 1:1 to four IAM Identity Center permission sets, each
carrying a single AWS managed policy (`AdministratorAccess`,
`PowerUserAccess`, `SecurityAudit`, `ReadOnlyAccess` respectively). Group
membership is Okta's job; what a group can *do* is the permission set's
job — two separate concerns, connected by SCIM on one side and an
`aws_ssoadmin_account_assignment` on the other.

**SAML/SCIM implementation note:** Okta's official "AWS IAM Identity
Center" catalog integration is required here, not a hand-built generic
SAML app — AWS's SCIM implementation has known group-creation limitations
(`Not Implemented` errors) against Okta's generic connector that the
purpose-built catalog integration handles correctly.

## Non-human identity (Terraform → AWS)

Every Terraform workspace that touches AWS authenticates via OIDC — no
static credentials, with one necessary exception:

```
HCP Terraform workspace → OIDC token → AWS IAM OIDC provider (per account)
  → assumes a workspace-scoped IAM role (trust condition pinned to
    org:workspace:project) → dynamic, short-lived credentials
```

The exception is the two bootstrap workspaces (`bootstrap-aws-trust`,
`bootstrap-mgmt-trust`), which *create* that OIDC trust and therefore can't
use it yet. Those are applied by a human via an MFA-gated IAM user
(`bootstrap-operator` / `mgmt-bootstrap-operator`) whose long-lived access
key can do nothing without a fresh MFA-derived STS session — the closest
practical equivalent, at this project's scale, to how a real AWS
Organization's management-account root user bootstraps trust once and is
rarely touched again.

## Account-level and org-level guardrails

| Layer | Mechanism | Scope |
|---|---|---|
| Account-wide config | S3 Block Public Access, EBS encryption-by-default, IMDSv2-required | `secure-platform-dev` only |
| Detection/audit | CloudTrail, Config, GuardDuty, Security Hub, Inspector, Access Analyzer | `secure-platform-dev` only |
| Org-wide, IAM-independent | SCP (`protect-audit-services`) | Attached from `secure-platform-mgmt`, constrains `secure-platform-dev` |

The SCP is the only control in this list that an admin IAM credential
inside `dev` cannot override — everything else could theoretically be
disabled by a sufficiently-privileged (or compromised) IAM principal within
the account; the SCP is the backstop that survives that.
