# Acceptance checklist

Tracks spec §16 directly. Check items off as they're demonstrably true —
not when the code merely exists, but when we've verified the behavior
(e.g. "OPA policies are tested" means tests run and fail on a bad policy,
not just that a `.rego` file exists).

- [x] HCP Terraform produces a separate, reviewable plan for the AWS dev environment.
- [ ] No static cloud credentials anywhere — not Terraform, not Actions, not K8s. (see tradeoff below — one necessary exception)
- [x] EKS is deployed with a secure network + identity baseline.
- [ ] External IdP provides SSO + MFA; SCIM model documented.
- [ ] Go API calls OPA and fails closed when OPA is down.
- [ ] OPA policies are tested and correctly deny an unauthorized action.
- [ ] A workload retrieves a permitted secret via its own identity; an unauthorized workload is denied.
- [x] CI scans source, dependencies, Terraform, and images before publish.
- [ ] GitOps deploys the signed image to the cluster by digest.
- [ ] Grafana shows service/cluster health; a controlled failure fires an alert.
- [ ] A recorded recovery exercise demonstrates restart, rollback, and backup restore.
- [ ] The Azure ADR maps every AWS control to a named Azure equivalent, with stub modules matching the interface.
- [ ] Docs explain design decisions, security tradeoffs, and implemented vs. planned controls.
- [ ] A CI secret-scan of Terraform plan/state output runs on every PR and blocks merge on a match.

## Known tradeoffs to revisit

- **`aws-dev-foundation`'s IAM policy widens read-only verbs to wildcards**
  (`ec2:Describe*`, `logs:Describe*`, `iam:Get*`/`List*`) instead of
  enumerating each one individually. Decided during Phase 3 networking work
  to reduce the temp-credential debugging cycle — every gap hit that day
  was a read-only verification action, never a mutating one, so the
  create/delete/modify actions stayed explicitly scoped while reads went
  broad. Revisit before calling this project interview-ready: either
  enumerate the exact read actions actually used (auditable via CloudTrail
  history), or explicitly document this as an accepted tradeoff with
  reasoning in an ADR.

- **`aws-dev-foundation`'s IAM policy for the CloudTrail S3 bucket wildcards read
  actions** (`s3:Get*`, `s3:List*`) scoped to that one bucket ARN, instead of
  enumerating each read sub-action individually. Same reasoning as the
  existing networking/IAM tradeoff above: the `aws_s3_bucket` resource reads
  back many bucket sub-configurations (ACL, CORS, encryption, versioning,
  etc.) during refresh, and each missing one cost a full plan/apply/debug
  cycle. Scoped to the specific bucket ARN, not account-wide.

- **`break-glass-dev`'s MFA factor is a TOTP authenticator app (Google
  Authenticator), not a phishing-resistant hardware key** — every other
  MFA-gated identity in this project (Okta SSO, `bootstrap-operator`) is
  built around phishing-resistant MFA; this is the one exception, driven
  by not having a spare hardware key on hand during Phase 3. Swap for a
  dedicated FIDO2 security key before calling this project
  interview-ready.

- **`bootstrap-operator` requires a static, long-lived IAM user access key**
  — this is the one static credential in the whole project, and it's a
  necessary exception rather than an oversight: at the very first bootstrap
  step (creating the OIDC providers and trust relationships that everything
  else assumes), no assumable role exists yet for it to use instead. Every
  mutating action on that identity is gated behind an active MFA session
  (`aws:MultiFactorAuthPresent` conditions on every sensitive statement), so
  the static key alone grants nothing beyond `sts:GetSessionToken`. Revisit
  whether this can be replaced with an MFA-gated `AssumeRole` flow from a
  separate, unprivileged base identity before calling this project
  interview-ready.

- **`bootstrap-operator`'s own IAM policy is a customer-managed policy
  (`arn:aws:iam::133857166442:policy/bootstrap-operator`) that lives in AWS
  but is not tracked in Terraform anywhere.** Discovered during Phase 5 when
  granting it new managed-policy permissions required editing it directly
  via the AWS CLI (`aws iam create-policy-version`), since there was no
  `.tf` file to change. Every other IAM policy in this project is Terraform
  state; this one is a manual, out-of-band exception because it has to
  exist before any Terraform-managed trust relationship can bootstrap it.
  Import it into Terraform state (`terraform import`) before calling this
  project interview-ready, so at least its *current* content is reviewable
  in git even if updates still require care around the bootstrap
  chicken-and-egg problem.

- **CI pins `cosign-release: 'v2.5.0'` in the `cosign-installer` action
  instead of tracking latest.** Cosign v3.x+ made OCI 1.1 referrers-only
  signature storage the unconditional default, with no flag to opt back
  into the classic `sha256-<digest>.sig` tag convention. Kyverno v1.19.0
  (the current latest chart release as of Phase 5) only checks that classic
  tag convention for keyless `verifyImages` — it has no support yet for
  discovering signatures via OCI 1.1 referrers. Pinning cosign to the last
  v2.x release keeps CI's signing format compatible with what Kyverno can
  actually verify. Revisit this pin once Kyverno ships referrers support
  (tracked upstream) — un-pinning too early will silently break the
  `require-cosign-signature` policy the same way it did before this pin was
  added, since Kyverno fails closed with "no signatures found" rather than
  an obvious version-mismatch error.
