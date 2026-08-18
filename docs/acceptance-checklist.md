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
