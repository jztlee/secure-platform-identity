# Policy catalog

Catalog of enforced policies: Terraform/OPA-Conftest policies on `terraform
plan` (spec §11) and Kyverno admission policies on the cluster (spec §8).
Each entry should say what's denied, why, and how it's tested. Populated
in Phase 5 (admission policy) and Phase 11 (Terraform policy).

## Kyverno admission policies (Phase 5)

### `require-cosign-signature`

**File:** [`kubernetes/policies/kyverno/require-cosign-signature.yaml`](../../kubernetes/policies/kyverno/require-cosign-signature.yaml)

**What's denied:** Any `Pod` referencing an image in the `platform-api` ECR
repository (by tag or by digest) that does not carry a valid cosign keyless
signature from this repo's `build-and-push` GitHub Actions workflow running
on `main`. `validationFailureAction: Enforce` — this blocks admission, it
does not just warn.

**Why:** Phase 7's CI pipeline signs every image it publishes with cosign
(keyless, via GitHub Actions OIDC → Fulcio). Without this policy, that
signature is purely advisory — nothing stops an unsigned or
differently-sourced image from being deployed anyway. This closes that gap:
the signing done in CI is now actually meaningful at deploy time, not just
recorded in a transparency log no one checks.

**Identity checked:**
- issuer: `https://token.actions.githubusercontent.com`
- subject: `https://github.com/jztlee/secure-platform-identity/.github/workflows/ci.yaml@refs/heads/main`

**Scope:** `imageReferences` covers both `platform-api:*` (tag) and
`platform-api@sha256:*` (digest) — the real `platform-api` Deployment
references images by digest, so the digest pattern is the one that matters
in practice; the tag pattern is kept for tag-referenced test/debug pods.
Deliberately *not* cluster-wide — this only matches the one ECR repository
this project controls the supply chain for. A cluster-wide version of this
rule would also try to verify signatures on `kube-system` images
(`aws-node`, `coredns`, `kube-proxy`) that were never signed by us and
would break the cluster's own system pods.

**Dependencies:** Kyverno's `kyverno-admission-controller` needs its own
AWS identity to read the signature artifact from ECR — granted via EKS Pod
Identity (`kyverno-ecr-read` IAM role, see
[`terraform/environments/dev/aws/kyverno-ecr-access.tf`](../../terraform/environments/dev/aws/kyverno-ecr-access.tf)),
not inherited from the node's own IAM role. Also depends on CI signing with
`cosign-release: 'v2.5.0'` specifically — see the cosign version-pin
tradeoff in `docs/acceptance-checklist.md` for why.

**How it's tested:** Manually verified in both directions —
1. A pod referencing the current `platform-api` deployment's signed image
   digest is admitted cleanly (`kubectl run` succeeds, pod reaches
   `Running`).
2. A pod referencing an unsigned image pushed to the same repository under
   a throwaway tag is rejected outright by the admission webhook, citing
   `no signatures found`.

No automated test exists yet for this policy (e.g. a Kyverno CLI test or a
CI step that intentionally tries to deploy an unsigned image and asserts
rejection) — only the manual verification above. Worth adding before
calling Phase 5 complete.

### `pod-security-restricted`

**File:** [`kubernetes/policies/kyverno/pod-security-restricted.yaml`](../../kubernetes/policies/kyverno/pod-security-restricted.yaml)

**What's denied:** Any `Pod` that (1) runs a privileged container, (2)
does not explicitly set `runAsNonRoot: true`, (3) does not explicitly set
`allowPrivilegeEscalation: false`, or (4) does not drop the `ALL`
capability set. `validationFailureAction: Enforce` — this blocks
admission.

**Why:** Covers the core of spec §8's Pod Security Standards (restricted)
requirement. This is the first subset of the full restricted profile —
host-namespace, hostPath, hostPort, seccomp, and volume-type restrictions
are still to come as a follow-up policy.

**Scope:** Cluster-wide (`match: kinds: [Pod]`), with `kube-system`
explicitly excluded on every rule. That exclusion is deliberate, not a
gap: `aws-node` (VPC CNI), `kube-proxy`, and `eks-pod-identity-agent` are
system components that inherently require privileged/root/host-level
access to do their job — they aren't misconfigured, that's what they are.
Matches Kyverno's own default behavior of excluding `kube-system` from
its bundled policies.

**Rollout process (worth preserving as the pattern for future policies):**
deployed first with `validationFailureAction: Audit` and `background:
true`, which scanned every already-running resource in the cluster
without blocking anything. That surfaced real, fixable violations in
components this project directly controls — `aws-load-balancer-controller`
(missing capability drop), the OTel Collector (missing security context
entirely), `kube-prometheus-stack`'s `node-exporter` (missing
privilege-escalation guard and capability drop), and the `opa` sidecar in
`kubernetes/base/platform-api/opa-deployment.yaml` (missing security
context entirely) — each fixed via Helm values or a direct manifest edit,
not exempted. Only after every fixable violation was resolved did the
policy flip to `Enforce`.

**How it's tested:**
1. Background-scan `PolicyReport`s confirmed every non-`kube-system`
   workload passes all four rules after the fixes above (`kubectl get
   policyreport -A`).
2. A deliberately privileged test pod (`--privileged`, no security
   context) was rejected outright by the admission webhook, correctly
   citing all four rules at once.

**Note on report staleness:** Kyverno's periodic background rescan runs
about once an hour by default; restarting `kyverno-background-controller`
does *not* force an immediate rescan, it just resets that timer. Existing
`PolicyReport`s for unchanged resources (like `kube-system`'s daemonsets)
can lag behind a policy change by up to that interval even though the
live policy is already correctly enforcing — don't mistake a stale report
for a broken exclusion; check the live `ClusterPolicy` object
(`kubectl get clusterpolicy <name> -o yaml`) instead.

**Still needed for Phase 5** (spec §8's full "enforced everywhere" list):
the remaining Pod Security Standards rules (host namespaces, hostPath,
hostPort, seccomp, restricted volume types), default-deny NetworkPolicies,
namespace ownership labels + quotas, and least-privilege RBAC (no wildcard
verbs/resources, no stray `cluster-admin` bindings outside
`break-glass-admin`).
