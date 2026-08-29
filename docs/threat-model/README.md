# Threat model

Started in Phase 3, extended as each new component introduces new attack
surface (spec §14) — not written once at the end. Sections marked **N/A
yet** cover components that don't exist in this project until a later
phase; they're listed now so the model's shape is complete, and filled in
when that phase actually lands.

## Token theft

**Bootstrap operator credentials.** `bootstrap-operator` /
`mgmt-bootstrap-operator` are long-lived IAM users, but their IAM policy
requires `aws:MultiFactorAuthPresent: true` on every action except
`sts:GetSessionToken`. A leaked long-term access key alone can do nothing
but request a session token — it still needs the physical MFA device to
produce anything usable. What's actually sensitive is a live *STS session*
(12-hour default), not the underlying key.

- **Realized during this build:** an AWS access key/secret and a SCIM
  bearer token were both accidentally pasted into a chat session during
  setup. Both were rotated immediately upon discovery. This is exactly the
  failure mode the MFA-gating is meant to blunt for the IAM keys — the
  SCIM token had no equivalent protection (see SCIM abuse, below).

**OIDC-derived credentials (HCP Terraform, GitHub Actions once built).**
Short-lived by design (session-duration bound), scoped by workspace/repo
trust conditions. A leaked token from a run log expires on its own; the
bigger risk is a trust-policy `sub` condition written too broadly (e.g.
`workspace:*` instead of a specific workspace name), which would let an
unrelated workspace assume a role it shouldn't.

**Break-glass credentials (`break-glass-dev`).** Same risk shape as the
bootstrap operator credentials above — a long-lived IAM access key that
alone can do nothing (zero permissions beyond `sts:AssumeRole`, itself
MFA-gated) until paired with a live MFA code. What's different: this
credential's MFA factor is TOTP rather than a hardware key (see
`docs/identity/README.md`'s "Known tradeoff"), and it's meant to sit
dormant far longer between uses than `bootstrap-operator` — both raise
the value of periodically confirming it still works and that its stored
secret material hasn't drifted or leaked, the same reasoning the SCIM
abuse section below applies to that token's rotation. Not yet on a
review schedule; natural to fold into the periodic access review process
once that cadence has real history behind it.

## Privilege escalation

**IAM role self-modification (the reason bootstrap is separate from
workload workspaces).** If `aws-dev-foundation`'s own IAM policy could
grant it permission to edit its own IAM role, a single compromised or
careless PR could add `iam:*` and self-escalate to full account admin,
with no human touching AWS credentials at any point. Mitigated
structurally: permission-granting Terraform lives only in the CLI-driven
bootstrap workspaces, applied by a human with a separately-authenticated
session — never the same pipeline that provisions routine infrastructure.

**`iam:PassRole` as a distinct grant.** Creating the Identity Center
recorder (and any resource that hands a role to an AWS service) required
`iam:PassRole` as its own explicit permission, separate from managing the
role itself. Without that split, any principal able to create a
service-linked role could pass an over-privileged role to a service it
controls.

**SCP as the backstop for compromised admin IAM.** Everything else in this
account (S3 BPA, IMDSv2, the audit services) could in principle be
disabled by a sufficiently privileged or stolen `platform-admin` IAM
Identity Center credential *inside* the dev account. The
`protect-audit-services` SCP is the one guardrail that credential
structurally cannot touch, since SCPs are only manageable from the
management account.

## Confused deputy

**Service-linked roles and cross-service KMS grants.** CloudTrail and
Config both need to write KMS-encrypted objects to S3 on our behalf — this
required explicit `Service` principal statements in the KMS key policy
(`cloudtrail.amazonaws.com`, `config.amazonaws.com`), each scoped with an
`aws:SourceAccount` (Config) or `aws:SourceArn` (CloudTrail) condition.
Without those conditions, any CloudTrail trail or Config recorder in *any*
AWS account could potentially invoke the key on our behalf — the classic
confused-deputy pattern where a trusted service is tricked into acting for
an unintended caller.

**`bucket-owner-full-control` on delivered log objects.** Both the
CloudTrail and Config S3 bucket policies require this ACL on every object
the service writes. Without it, a written log object's ACL could omit the
bucket owner from having control over it — meaning the account could lose
the ability to manage its own audit logs, a subtle version of the same
confused-deputy class of problem.

## SCIM abuse

**Bearer token as a standing credential.** IAM Identity Center's SCIM
access token is a single, long-lived bearer credential with no MFA
equivalent — unlike the IAM bootstrap users, nothing gates its use beyond
possessing the string itself. It was rotated immediately after an
accidental exposure during setup (see Token theft, above), but the
underlying design gap remains: **this token should be treated as
maximally sensitive and rotated on a schedule**, not just after an
incident. Not yet automated — a candidate for a documented recurring
task once the project has a place for scheduled operational hygiene.

**Push-Groups vs. individual assignment.** Group push syncs group
*existence and membership* from Okta into Identity Center; it does not,
by itself, guarantee a user is *authorized* to sign in anywhere — that
still requires the group to be explicitly assigned to the SAML app.
Misconfiguring this (assigning the wrong group, or forgetting to assign
any group) would either lock out legitimate users or, worse, leave a
default/broad group assigned unintentionally. Currently mitigated by
having exactly one group (`platform-admin`) assigned, matching one
provisioned user.

## Terraform state / secret exposure

**State is not encrypted by `sensitive = true`.** HCP Terraform encrypts
state at rest, but a `sensitive` attribute only hides a value from
CLI/plan *output* — the raw value is still in the state file. This
project's practice: never generate real secret material via Terraform
(`random_password` and similar are unused); create containers (KMS keys,
buckets) via Terraform, populate actual secret values out-of-band. No
value has been put in an `output` block that shouldn't be there.

**State-read access is not yet separately scoped from workspace access**
(spec §5 calls for this — security-auditor/read-only teams should get
workspace visibility without raw state download). Not yet implemented;
currently only the two bootstrap-adjacent IAM users and whoever has HCP
Terraform org access can reach state. Revisit once the `security-auditor`
Identity Center permission set is actually in regular use.

**Pre-apply secret-pattern scanning of plan/state output** — required by
spec §16 acceptance criteria, not yet built. Belongs in the CI/CD phase
(Phase 7).

## Supply chain compromise

**Provider version pinning.** `.terraform.lock.hcl` is committed for every
Terraform directory, so provider checksums are verified on every run —
already in place since Phase 2.

**Mutable GitHub Action tags, unpinned Actions.** N/A yet — no GitHub
Actions workflow exists until Phase 7. Documented here as a known
requirement (SHA-pinning every Action, never a tag) for when that phase
starts.

**Branch protection as a supply-chain control on `main` itself.** In
place: a ruleset requiring a PR before merge, blocking force-pushes and
branch deletion, with an empty bypass list (applies to the repo owner
too). Gap acknowledged in `docs/study-guide.md`: no required reviewer
count or required status checks yet — reasonable for a solo contributor,
worth revisiting if this repo ever gains a second contributor.

## K8s escape — N/A yet

No EKS cluster exists until Phase 4. Will cover: pod-to-node breakout,
privileged container abuse, Kyverno admission-policy bypass, and how EKS
Pod Identity's trust model differs from IRSA's, once that phase lands.

## Agent delegation — N/A yet

No AI/agent principal exists until the Go platform API's delegation model
is built (Phase 6, per spec §9's non-human identity table — "Sample AI
service, Delegated short-lived token"). Will cover: how the initiating
user and full delegation chain get preserved in audit output, and what
happens if a delegated token outlives its intended scope.
