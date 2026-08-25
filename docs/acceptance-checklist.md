# Acceptance checklist

Tracks spec §16 directly. Check items off as they're demonstrably true —
not when the code merely exists, but when we've verified the behavior
(e.g. "OPA policies are tested" means tests run and fail on a bad policy,
not just that a `.rego` file exists).

- [ ] HCP Terraform produces a separate, reviewable plan for the AWS dev environment.
- [ ] No static cloud credentials anywhere — not Terraform, not Actions, not K8s.
- [ ] EKS is deployed with a secure network + identity baseline.
- [ ] External IdP provides SSO + MFA; SCIM model documented.
- [ ] Go API calls OPA and fails closed when OPA is down.
- [ ] OPA policies are tested and correctly deny an unauthorized action.
- [ ] A workload retrieves a permitted secret via its own identity; an unauthorized workload is denied.
- [ ] CI scans source, dependencies, Terraform, and images before publish.
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
