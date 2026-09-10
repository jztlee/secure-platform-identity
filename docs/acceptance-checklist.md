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

- **`require-resource-hardening` (read-only root filesystem + explicit
  resource requests/CPU limits) is scoped to the `platform-api` namespace
  only, not cluster-wide.** Every third-party chart installed so far —
  Argo CD, cert-manager, External Secrets Operator, Kyverno's own
  controllers, and the kube-prometheus-stack components — fails this
  policy, and fixing it properly is real, uneven work: Argo CD's chart sets
  *no* resource configuration at all by default (confirmed via `kubectl get
  deployment ... -o jsonpath='{.spec.template.spec.containers[0].resources}'`
  returning `{}`), and since it was installed via a one-time manual `helm
  install` rather than an Argo CD Application, fixing it means a manual
  `helm upgrade` with per-component values across ~7 sub-components — not
  a quick edit, and not committed anywhere as code the way everything else
  in this project is. Deliberate tradeoff, not an oversight: these
  components already pass every *other* policy enforced tonight (non-root,
  no privilege escalation, dropped capabilities), so the incremental risk
  reduction from read-only-root and CPU limits specifically is secondary,
  weighed against an estimated 1.5–2.5 hours of additional work with real
  odds of hitting another genuine complication along the way (e.g. Argo
  CD's `repo-server` clones git repos and renders Helm charts, and
  plausibly needs writable scratch space that a read-only root filesystem
  would break). The honest gap this leaves: no CPU limit on these
  components means a bug or compromise in any of them could consume more
  of a node's resources than intended — a real noisy-neighbor risk on a
  3-node cluster, not a theoretical one. Revisit before calling this
  project interview-ready, ideally via a namespace-label-based scope
  (`namespaceSelector` on a `workload-tier` label) rather than a hardcoded
  namespace name, so extending coverage later doesn't require editing the
  policy itself each time.
