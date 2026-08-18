# Documentation index

Source of truth for scope and architecture is [`spec.md`](spec.md). This
directory holds the supporting documentation called for in spec §14, one
subdirectory per category. Most of these are empty skeletons right now —
they get populated as we reach the phase that produces that content (see
spec §15 for delivery order).

| Directory | Spec §14 category | Populated in phase |
|---|---|---|
| [`architecture/`](architecture/) | Architecture + data flow diagrams | Ongoing, starting Phase 3 |
| [`terraform/`](terraform/) | Terraform module guide and workspace map | Phase 2 onward |
| [`azure-portability/`](azure-portability/) | AWS control mapping + Azure portability ADR | Phase 10 |
| [`identity/`](identity/) | Identity model (human + non-human) and entitlement graph | Phase 3, 6 |
| [`threat-model/`](threat-model/) | Threat model | Ongoing, starting Phase 3 |
| [`policy-catalog/`](policy-catalog/) | Policy catalog (Terraform + admission) | Phase 5, 11 |
| [`cicd/`](cicd/) | CI/CD and GitOps workflow guide | Phase 7, 8 |
| [`runbooks/`](runbooks/) | Incident runbooks | Phase 9 |
| [`dr/`](dr/) | DR plan with recovery objectives and restore-test results | Phase 9 |
| [`cost/`](cost/) | Cost/capacity plan | Phase 9, 12 |
| [`adr/`](adr/) | ADRs for major technology choices | Ongoing |

[`acceptance-checklist.md`](acceptance-checklist.md) tracks spec §16 as a
literal checklist — updated at the end of each phase, not just at the end
of the project.
