# Identity model

Human and non-human identity, and the entitlement graph design (spec §9).
Populated in Phase 3 (human identity, SSO/SCIM — this section); the
Go API authorization / entitlement graph half comes in Phase 6.

## Human identity

**Directory of record:** Okta (Integrator Free Plan). Authoritative — IAM
Identity Center's identity source is configured as an external IdP, not
its own built-in directory, so a user's existence and group membership is
defined in Okta and mirrored outward, never the reverse.

**Groups → roles.** Four Okta groups, SCIM-synced into IAM Identity
Center, each mapped to exactly one permission set on the dev account:

| Okta group | Permission set | AWS managed policy | Intended for |
|---|---|---|---|
| `platform-admin` | `platform-admin` | `AdministratorAccess` | Full platform administration — Terraform, cluster admin |
| `developer` | `developer` | `PowerUserAccess` | Application development, short of IAM/org management |
| `security-auditor` | `security-auditor` | `SecurityAudit` | Read-only, scoped for security auditing |
| `read-only` | `read-only` | `ReadOnlyAccess` | General read-only visibility |

**MFA:** phishing-resistant only (Okta Verify with FastPass, or
WebAuthn/FIDO2) — not SMS or bare TOTP, both of which are vulnerable to
real-time relay phishing. Enforced at the Okta account level once IAM
Identity Center's identity source changed to external IdP (AWS deletes its
own MFA configuration at that point and defers entirely to the IdP's).

**Provisioning path:** Okta → SAML (authentication) + SCIM
(user/group lifecycle) → IAM Identity Center → permission set + account
assignment → federated console/CLI access to `secure-platform-dev`.
Deprovisioning is automatic in the same direction: removing a user from a
group in Okta, or deactivating their Okta account, revokes the
corresponding IAM Identity Center access via the same SCIM channel
("Deactivate Users" provisioning action) — no manual AWS-side cleanup
step.

**Known gap:** only one human (the project operator) is provisioned today,
in `platform-admin`. The `developer`, `security-auditor`, and `read-only`
groups exist and have working permission sets, but no user has been
assigned to them yet — there's nothing to test group-level least-privilege
behavior against until a second identity exists. Worth doing before
calling the identity model demonstrably complete, not just structurally
complete.

## Non-human identity (v1, built)

| Principal | Auth method | Scope |
|---|---|---|
| HCP Terraform (`aws-dev-foundation`) | OIDC federation | `secure-platform-dev`, workspace-scoped trust condition |
| HCP Terraform (`aws-mgmt-scp`) | OIDC federation | `secure-platform-mgmt`, workspace-scoped trust condition |
| Human bootstrap operator (`bootstrap-operator`) | MFA-gated IAM user → STS session | `secure-platform-dev`, IAM/OIDC-provider actions only |
| Human bootstrap operator (`mgmt-bootstrap-operator`) | MFA-gated IAM user → STS session | `secure-platform-mgmt`, IAM/Organizations/Identity-Center actions only |
| CloudTrail (service principal) | KMS key policy grant, S3 bucket policy grant | `secure-platform-dev`, scoped by `aws:SourceArn` |
| AWS Config (service principal) | KMS key policy grant, S3 bucket policy grant, service-linked role | `secure-platform-dev`, scoped by `aws:SourceAccount` |
| GuardDuty / Security Hub / Inspector (service-linked roles) | AWS-managed, not user-editable | `secure-platform-dev` |

**Why two bootstrap operators, not one shared across accounts:** each
AWS account's OIDC trust is independent — reusing one human credential
across both would mean a single compromised credential (or a single
person's MFA device) controls the ability to grant permissions in *both*
accounts at once. Separate credentials keep that blast radius contained
per account, same reasoning as why SCPs live in a different account than
the thing they protect.

**Not yet built:** GitHub Actions OIDC federation (Phase 7), EKS workload
Pod Identity (Phase 4), internal service mTLS (Phase 5), and the AI
principal's delegated short-lived token (Phase 6) — all appear in spec
§9's full non-human identity table but don't exist in this project until
their respective phases.

## Entitlement graph

Not yet built — this is explicitly a Phase 6 deliverable (Go API
authorization + OPA), maintaining the graph of users, groups, pipelines,
workloads, agents, roles, and resources, and logging every authorization
decision with subject/action/resource/result/correlation ID. The identity
*plumbing* this section documents (Okta → SCIM → Identity Center →
permission sets) is the human-identity input that graph will eventually
need to reason about; it doesn't exist as a queryable graph yet.
