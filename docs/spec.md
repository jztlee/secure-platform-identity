# Secure Platform and Identity Infrastructure — AWS v1, Azure-Portable by Design

## 1. Product brief

A portfolio-grade internal developer platform, built on AWS, with identity
and policy enforcement built into the workflow rather than bolted on.
Engineering teams provision approved infrastructure and deploy containerized
services through a secure paved road.

**v1 builds AWS end-to-end.** Azure is designed and documented as a phase-2
extension (§2) — every AWS component has a named Azure equivalent, mapped in
an ADR, with stub Terraform modules matching the interface. The point is
proving you can design a portable pattern, not proving you can click through
two consoles while still learning Kubernetes and Go.

**Audience:** Cloud Platform Engineering, Platform Security Engineering, IAM
Security Engineering, and Identity Infrastructure hiring teams. The project
should demonstrate IaC, Kubernetes operations, CI/CD, zero-trust identity,
policy as code, observability, and operational resilience — as real, working
systems, not diagrams.

**Non-goals**
- No production cloud deployment without explicit account IDs, billing controls, and approval.
- No secret values, private keys, or live tokens in Git, ever.
- Not a general-purpose IdP — integrate existing identity services via OIDC, OAuth 2.0, SAML, SCIM.
- No Azure infrastructure deployed in v1 — designed and documented only (§2).
- CyberArk and HashiCorp Vault are documented extension paths, not required for v1.

## 2. Scope call — read this before building

This is a single-cloud build with a documented, portable design for a second
cloud — not two half-built clouds. You're learning Kubernetes and Go from
zero at the same time; doubling every cloud-specific integration (Entra vs.
IAM Identity Center, ACR vs. ECR, AKS vs. EKS) would cost weeks without
deepening the skills the target roles actually test.

- **AWS account:** single `dev` workload account with the security baseline
  (SCPs, GuardDuty, Security Hub, CloudTrail, IAM Identity Center) fully
  implemented. Document the full Organizations model (`management`,
  `security`, `log-archive`, `shared-services`, `dev/staging/prod`) as the
  target state in `docs/`, rather than provisioning all seven.
- **Sentinel vs. OPA:** Sentinel requires a paid HCP Terraform tier. Use
  OPA/Conftest (or `terraform plan` + `checkov`/`tfsec`) for policy
  enforcement in CI; document Sentinel as the Terraform Enterprise
  equivalent.
- **Azure:** fully designed at the module level — Terraform module stubs
  with documented inputs/outputs, plus an ADR mapping every AWS component to
  its Azure equivalent (AKS↔EKS, ACR↔ECR, Key Vault↔Secrets Manager, Entra
  Workload Identity↔Pod Identity, Defender for Cloud↔GuardDuty/Security Hub)
  — but not deployed. "I built AWS first and designed it to port cleanly to
  Azure — here's exactly what changes" is a legitimate, defensible interview
  answer, and it's honest about what you actually built.

Everything below reflects AWS as the only deployed cloud. Azure equivalents
are called out as **(designed, not built)** where relevant.

## 3. Architecture

flowchart TB
  User["Developer or platform operator"] --> IdP["Okta\nSSO MFA SCIM"]
  IdP --> TFC["HCP Terraform"]
  IdP --> AWSAccess["AWS IAM Identity Center"]

  GitHub["GitHub repositories"] --> TFC
  GitHub --> CI["GitHub Actions\ntest scan build sign"]
  TFC --> OIDC["OIDC short lived credentials"]
  OIDC --> AWS

  subgraph AWS["AWS workload account"]
    EKS["EKS private cluster"]
    ECR["ECR"]
    AWSSecrets["Secrets Manager and KMS"]
    AWSObs["CloudWatch GuardDuty Security Hub"]
    ECR --> EKS
    EKS --> AWSSecrets
    EKS --> AWSObs
  end

  CI --> ECR
  CI --> GitOps["GitOps repository"]
  GitOps --> Argo["Argo CD"]
  Argo --> EKS

  API["Go platform API\nOPA authorization"] --> EKS
  Policy["OPA / Conftest\nTerraform policy as code"] --> TFC

**Azure portability (designed, not built):** every AWS node above has a named
Azure equivalent — AKS for EKS, ACR for ECR, Key Vault for Secrets Manager,
Entra Workload Identity for Pod Identity, Defender for Cloud for
GuardDuty/Security Hub. The `azure-*` Terraform modules in the repo (§4)
exist as stubs with matching interfaces, documented in an ADR.

## 4. Repository layout

```
secure-platform-identity/
  terraform/
    bootstrap/{hcp-terraform, aws-oidc-trust}/
    modules/{aws-networking, aws-eks, aws-security, aws-identity,
              shared-observability, hcp-workspace,
              azure-networking, azure-aks, azure-security, azure-identity}/  # azure-* = stubs, not applied
    environments/{dev,staging,prod}/aws/
    policies/opa/
  platform-api/{cmd/api, internal, Dockerfile, tests}/
  kubernetes/{base, aws, identity, observability, batch}/
  gitops/
    clusters/{aws-dev, aws-prod}/
    applications/
  .github/workflows/
  docs/
```

## 5. HCP Terraform design

**Projects:** `bootstrap`, `shared-platform`, `nonproduction`, `production`

**Workspaces (v1, built):** `bootstrap-aws-trust`, `shared-identity`,
`aws-dev-foundation`, `aws-dev-eks`, `aws-prod-foundation`, `aws-prod-eks`

**Workspaces (documented, not created):** `bootstrap-azure-trust`,
`azure-dev-foundation`, `azure-dev-aks`, `azure-prod-foundation`,
`azure-prod-aks`

**Requirements:** VCS-driven runs from protected branches; remote state and
execution; project/workspace RBAC (platform admin, developer, security
auditor, read-only); dynamic provider credentials via OIDC (no static keys,
ever); sensitive variables only for inputs that truly can't be eliminated;
policy sets attached by workspace tags (`environment:prod`, `cloud:aws`);
mandatory review before any prod apply; cost estimation with a documented
approval threshold. **State access is scoped tighter than general workspace
access** — security-auditor and read-only teams get workspace visibility,
not raw state download; only platform-admin and the CI service account can
pull state. A pre-apply check (run task or CI step) scans
`terraform show -json` for secret patterns before any plan proceeds.

## 6. AWS foundation

- **Accounts:** one `dev` workload account (see §2); document the rest of the
  Organizations model.
- **Networking:** multi-AZ VPC — public subnets (ALB, NAT), private app
  subnets (EKS nodes), private data subnets; VPC endpoints for S3, ECR, STS,
  Secrets Manager, CloudWatch; flow logs to central logging; no unrestricted
  admin/DB ingress.
- **EKS:** private nodes across ≥2 AZs; separate system/application node
  groups; **EKS Pod Identity** for workload AWS access (the current AWS
  standard — simpler trust policy than IRSA; document IRSA as the prior
  approach for comparison); restricted API endpoint access; audit logging on;
  **Karpenter** for autoscaling (the modern default over Cluster Autoscaler —
  worth naming explicitly in interviews).
- **Security:** IAM Identity Center federated to the external IdP (SAML +
  SCIM) with platform admin/developer/security-auditor/read-only permission
  sets; separate OIDC roles for HCP Terraform and GitHub Actions, each scoped
  by workspace/repo/branch conditions; KMS everywhere (S3, EBS, RDS, Secrets
  Manager, backups); Secrets Manager rotation for DB credentials; CloudTrail
  org trail + Config + GuardDuty + Security Hub + Inspector + Access
  Analyzer; WAF in front of public endpoints; SCPs blocking public S3,
  disabled audit services, unapproved regions, unencrypted resource creation;
  **IMDSv2 required** on every EC2/node instance (no IMDSv1 fallback); S3
  Block Public Access enabled at the account level; EBS encryption by default
  enabled per region; IAM policies scoped to specific resource ARNs, not
  wildcard actions/resources — reviewed against Access Analyzer findings
  before merge.

## 7. Azure target design (designed, not built in v1)

Document, don't deploy: a VNet mirroring the AWS VPC layout (app/data/private
endpoint subnets, least-privilege NSGs); AKS as the EKS equivalent (private
cluster, AKS Workload Identity mirroring Pod Identity, Azure RBAC); Entra ID
app registrations and service principals using **federated identity
credentials** rather than client secrets, following the same
no-long-lived-secret principle as AWS; Key Vault as the Secrets Manager
equivalent (RBAC, private endpoints only, soft delete, purge protection);
Defender for Cloud and Azure Policy as the GuardDuty/Security Hub/SCP
equivalent. Write this as an ADR with a side-by-side control mapping table —
this is the artifact that proves portability without doubling the build.

## 8. Kubernetes baseline and admission policy

Bootstrap components via Terraform Helm resources; everything after that is
managed by Argo CD: Argo CD itself, cert-manager (internal CA issuer),
External Secrets Operator, Prometheus/Alertmanager/Grafana, an OTel
Collector, **Kyverno** for admission control (pick one over Gatekeeper —
Kyverno's YAML policies are faster to write and demo than Rego for this
scope), ExternalDNS if a zone is available, AWS Load Balancer Controller.

**Enforced everywhere:** namespace ownership labels + quotas; Pod Security
Standards (restricted); default-deny NetworkPolicies; non-root, read-only-fs,
dropped capabilities, seccomp default, explicit resource requests/limits;
**immutable image digests, never mutable tags**; workload identity only —
never static cloud credentials in Kubernetes secrets. Admission policy denies
privileged containers, root/privilege-escalation/writable-root-fs, missing
resource limits, mutable tags, **unsigned images** (Kyverno `verifyImages`
against the cosign key/keyless signature from §11 — this is enforced, not
optional, since CI already signs every image), and workloads missing
required labels or NetworkPolicy. Kubernetes RBAC is least-privilege — no
wildcard verbs/resources in ClusterRoles, no `cluster-admin` bindings outside
a documented, logged break-glass identity. API server and audit logs ship to
CloudWatch with a documented minimum retention.

## 9. Identity platform

**Human identity:** external IdP is the authoritative directory; SSO +
phishing-resistant MFA required for privileged access; SCIM provisions IAM
Identity Center; least-privilege roles, periodic access reviews,
time-bounded emergency access, immutable audit logs for privileged actions.

**Non-human identity (v1, built):**

| Principal | Auth method | Scope |
|---|---|---|
| HCP Terraform | OIDC federation | Workspace + cloud environment |
| GitHub Actions | OIDC federation | Repo, branch, workflow |
| EKS workload | Pod Identity | One K8s service account |
| Internal service | mTLS + short-lived token | Service-to-service API |
| Sample AI service | Delegated short-lived token | Explicit tools/actions only |

**Non-human identity (Azure, designed not built):**

| Principal | Auth method | Scope |
|---|---|---|
| AKS workload | AKS Workload Identity | One K8s service account |
| HCP Terraform → Azure | OIDC federation | Workspace + subscription |

**Authorization:** Go API exposes `/healthz`, `/v1/namespaces`, `/v1/authorize`;
calls OPA and **fails closed** if OPA is unreachable; Rego policy lives in Git
and is tested; maintain an entitlement graph (users, groups, pipelines,
workloads, agents, roles, resources); log every decision (subject, action,
resource, result, correlation ID, timestamp); the AI principal must preserve
the initiating user and full delegation chain in audit output.

**mTLS:** cert-manager issues and renews workload certs; document how a
service mesh or workload-identity platform would enforce peer identity for
production mTLS — server TLS alone is not service-to-service authorization.

## 10. Secrets and key management

AWS workloads pull from Secrets Manager via workload identity + External
Secrets Operator. Enable rotation where supported and document how it's
tested. Use KMS keys for encryption, with dedicated keys per environment for
sensitive workloads. ACM for externally managed TLS; cert-manager for
in-cluster certs. GitHub secret scanning, dependency scanning, and
pre-commit secret checks. Terraform may provision vaults/keys/roles but must
never commit real secret values or expose them in outputs. *(Key Vault as
the Azure equivalent — designed, not built; see §7.)*

**Terraform state security:** state stores full resource attributes in
plaintext — `sensitive = true` hides a value from CLI/plan output, it does
**not** encrypt it in state. Treat state itself as a secret store: HCP
Terraform encrypts it at rest, but state-read access is scoped separately
from workspace access (§5). Prefer never generating real secret material in
Terraform at all — create the Secrets Manager *container* via Terraform,
populate the value out-of-band; avoid `random_password` and similar
resources where a federated credential or an external write will do. Never
put a sensitive value in an `output` block, even a marked-sensitive one. CI
scans `terraform show -json` for secret patterns before any apply (§11).

*Extension path:* Vault for dynamic DB credentials; CyberArk for privileged
human sessions. Neither is required for v1.

## 11. CI/CD

**GitHub Actions:** format/validate Terraform → lint + IaC security scan →
**scan plan output for secret patterns** → Go format/test/static analysis →
secret + dependency scanning → build non-root Docker image → generate SBOM →
image vuln scan → sign (cosign) and publish by immutable digest to ECR →
open a reviewed PR against the GitOps repo. Uses OIDC, repo-scoped claims,
branch protection. GitHub Actions may validate Terraform but **never applies
production infrastructure** — that stays in HCP Terraform.

**Supply chain / workflow hardening:** every Action is pinned to a full
commit SHA, never a tag or branch (tags are mutable and a known attack
vector); each workflow declares only the `permissions:` it needs — default
`contents: read`, add `id-token: write` only on the OIDC-federated jobs;
production promotion runs behind a GitHub Environment with required
reviewers, distinct from ordinary branch-protection review; `.terraform.lock.hcl`
is committed so provider checksums are verified on every run.

**Argo CD:** reconciles from a dedicated GitOps repo; auto-deploys to dev
after CI passes; requires a reviewed PR to promote to staging/prod; surfaces
drift and health; rollback = revert Git.

**Terraform policy (OPA/Conftest on `terraform plan`):** deny or require
approval for public object storage; unencrypted disks/DBs/secrets/backups;
resources outside approved regions; missing owner/environment/cost-center/
classification tags; wide-open admin or DB ports in security groups; K8s
clusters without private nodes or audit logs; missing diagnostics or threat
detection; unapproved prod compute sizes; cost increases above threshold.

## 12. Observability and resilience

**Metrics:** Prometheus for cluster/node/container/workload/API metrics;
Grafana dashboards for API availability, latency, error rate, saturation,
deployment health, node pressure, queue performance; SLOs for API
availability, deployment success, and queue latency.

**Logging:** K8s and control-plane logs to CloudWatch; centralized
CloudTrail; alerts on failed privileged auth, secret-read anomalies, OIDC
trust changes, policy denials, unexpected role assumptions, anomalous
workload behavior. *(Log Analytics/Defender alerting as the Azure
equivalent — designed, not built.)*

**Resilience:** multi-AZ cluster and node pools; PDBs and HPA; KEDA-driven
batch workers (SQS); backup/restore for stateful services; documented
cross-region DR design with an RTO/RPO; test pod failure, node loss, failed
rollout, queue backlog, and backup restore in a non-prod environment — with
evidence, not just a runbook.

## 13. Go platform API

| Endpoint | Behavior |
|---|---|
| `GET /healthz` | Health state |
| `POST /v1/namespaces` | Generates a namespace manifest after authorization |
| `POST /v1/authorize` | Sends subject/action/resource to OPA, returns decision |
| `GET /metrics` | Prometheus metrics |

Request validation, structured JSON logs, correlation ID propagation, OTel
instrumentation, unit tests for validate/allow/deny/OPA-down paths, non-root
multi-stage Docker build, K8s readiness/liveness probes, resource limits,
NetworkPolicy, mTLS-ready, workload identity, no sensitive data or tokens in
logs.

## 14. Documentation (`docs/`)

- Architecture + data flow diagrams
- Terraform module guide and workspace map
- **AWS control mapping (built) + Azure portability ADR (designed target)**
- Identity model (human + non-human) and entitlement graph design
- Threat model: token theft, privilege escalation, confused deputy, SCIM
  abuse, supply chain compromise (incl. mutable Action tags, unpinned
  providers), Terraform state/secret exposure, K8s escape, agent delegation
- Policy catalog (Terraform + admission)
- CI/CD and GitOps workflow guide
- Incident runbooks: credential leak, compromised workload, failed rollout, unavailable IdP
- DR plan with recovery objectives and restore-test results
- Cost/capacity plan
- ADRs for major technology choices (including the §2 scope calls and the AWS-first decision)

## 15. Delivery order

1. Repos, branch protection, docs skeleton.
2. HCP Terraform org/projects/workspaces + OIDC bootstrap trust (AWS).
3. AWS dev foundation (network, identity, logging, security baseline).
4. EKS with private nodes.
5. Cluster baseline services + admission policy.
6. Go platform API + OPA policy, tested.
7. GitHub Actions pipeline publishing signed images.
8. Argo CD wired to EKS via GitOps.
9. Observability, SLOs, alerts, batch compute, failure testing.
10. Azure portability ADR + stubbed `azure-*` Terraform modules (documented, not applied).
11. Prod workspace config, mandatory policies, approval workflow — **no prod apply without account approval.**
12. Finish docs; record a short demo.

## 16. Acceptance criteria

- HCP Terraform produces a separate, reviewable plan for the AWS dev environment.
- No static cloud credentials anywhere — not Terraform, not Actions, not K8s.
- EKS is deployed with a secure network + identity baseline.
- External IdP provides SSO + MFA; SCIM model documented.
- Go API calls OPA and fails closed when OPA is down.
- OPA policies are tested and correctly deny an unauthorized action.
- A workload retrieves a permitted secret via its own identity; an
  unauthorized workload is denied.
- CI scans source, dependencies, Terraform, and images before publish.
- GitOps deploys the signed image to the cluster by digest.
- Grafana shows service/cluster health; a controlled failure fires an alert.
- A recorded recovery exercise demonstrates restart, rollback, and backup restore.
- The Azure ADR maps every AWS control to a named Azure equivalent, with stub modules matching the interface.
- Docs explain design decisions, security tradeoffs, and implemented vs. planned controls.
- A CI secret-scan of Terraform plan/state output runs on every PR and blocks merge on a match.

## 17. Guardrails

Placeholder values for all tenant/subscription/account IDs, regions, domains,
image refs. Pin all provider/module/image versions; **pin all GitHub Actions
to a commit SHA**, never a tag. `.gitignore` for state, secret-bearing var
files, kubeconfig, env files, build output — and never rely on `.gitignore`
alone: pre-commit and CI secret scanning catch what slips past it. Small
reusable Terraform modules with tests/examples. `terraform fmt`/`validate` +
linting + security scanning in CI. Cloud foundation, cluster add-ons, and app
deployment stay in separate code paths (no circular deps). Default-deny for
network and authorization. Every resource tagged for owner, environment, cost
center, classification, managed-by.

## 18. Prompt to give Claude

Use this spec as source of truth. Implement incrementally, in delivery
order, AWS-only for v1 — do not build Azure infrastructure; the `azure-*`
modules stay as documented stubs (§7, §10). Start with repo layout,
Terraform provider config, bootstrap modules, and nonsecret example
variables — no live credentials, no cloud apply, no secrets in code or
examples. For each phase: explain the files being added and the security
decisions behind them in plain language, since I'm learning Kubernetes and
Go for the first time on this project — a working checkpoint before moving
to the next phase; add validation and tests wherever locally verifiable;
mark all account/tenant/image/cert/DNS values as clear placeholders; update
docs and the acceptance checklist before moving on.
