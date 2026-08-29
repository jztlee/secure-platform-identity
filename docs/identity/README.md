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

**Verification status: confirmed working end-to-end.** Beyond Okta's
System Log (`user.authentication.sso` SUCCESS) and AWS CloudTrail
(confirming IAM Identity Center provisioned all four permission sets as
real IAM roles in the dev account, matching Terraform exactly), a live
browser session was confirmed reaching the AWS access portal and listing
`secure-platform-dev` with the `platform-admin` role available to assume.

**Debugging note, for anyone hitting the same wall:** getting here took a
long troubleshooting pass through several real but ultimately secondary
issues — an org-wide API rate-limit check (a red herring; those buckets
showed zero violations), a genuine `system.client.rate_limit.violation`
and a `security.session.detect_client_roaming` denial (both real events,
likely triggered by repeatedly retrying a handshake that could never
succeed), and a legitimate bug fix along the way (the `platform-admin`
Okta user accidentally shared its email with the management account's AWS
root user — fixed via a `+`-alias, same pattern as the dev account's root
email). **The actual root cause** was that the official "AWS IAM Identity
Center" catalog app's **Advanced Sign-on Settings** fields (AWS SSO ACS
URL, AWS SSO issuer URL) were never populated after switching from the
broken custom SAML app — a structural gap specific to that app template,
not a rate limit or session issue at all. Worth remembering: when an app
integration is switched mid-setup, re-verify *every* field the new
template introduces, not just the ones that carried over conceptually
from the old one.

**Periodic access review.** Quarterly review of the human-identity
entitlement chain — Okta group membership, IAM Identity Center account
assignments (checked for drift against those groups), and console
sign-in history per permission set to flag assigned-but-unused access.
Reviewer is the project operator; at solo scale there's no separation of
duties on this, an accepted tradeoff rather than a hidden gap. Each
review appends a dated entry (reviewer, findings, actions taken) to
`docs/identity/access-reviews.md` rather than being merely asserted.
Off-cycle review is also triggered by any group/permission-set change or
offboarding, not just the quarterly cadence.

**Time-bounded emergency access (break-glass).** A native IAM path into
`secure-platform-dev` that doesn't depend on Okta or IAM Identity Center
being available — deliberately independent, since an IdP outage or
compromise is exactly the scenario this exists for. `break-glass-dev` is
a native IAM user (created out-of-band, like `bootstrap-operator`, not
in Terraform) with no permissions of its own beyond assuming one role,
`break-glass-admin`. That role carries `AdministratorAccess` and a
`max_session_duration` of 3600 seconds — AWS enforces this cap directly,
not just by policy convention: verified 2026-08-28 by requesting a
12-hour session and getting an outright rejection
(`ValidationError: ... DurationSeconds exceeds the MaxSessionDuration`),
then confirming a normal request succeeds with an expiration ~1 hour out
and genuinely grants `AdministratorAccess` (checked via `iam:ListUsers`).
The role's trust policy requires `aws:MultiFactorAuthPresent: true`; the
user's own identity policy separately requires it too and is scoped to
`sts:AssumeRole` on that one role ARN only.

**Known tradeoff:** MFA for `break-glass-dev` is a TOTP code (Google
Authenticator) rather than a phishing-resistant hardware key — the one
place in this project's identity model that doesn't meet the
phishing-resistant-only bar set for Okta (see above). Accepted for Phase
3 given not having spare hardware on hand; tracked in
`docs/acceptance-checklist.md` → "Known tradeoffs to revisit" as
something to swap for a dedicated FIDO2 key before this project is
interview-ready.

**Mechanism built and tested; formal runbook still pending.** The
assume-role path has been exercised end-to-end, as described above. The
documented, rehearsed incident procedure for "IdP unavailable"
(`docs/runbooks/`'s eventual `unavailable-idp.md`) is deliberately
deferred to Phase 9, alongside the failure testing that validates every
runbook. What exists now is a working mechanism; what's still missing is
a tested walkthrough of using it under realistic incident conditions,
not just a clean terminal.

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
