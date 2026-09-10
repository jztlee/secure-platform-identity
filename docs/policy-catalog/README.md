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
(`kubectl get clusterpolicy <name> -o yaml`) instead. If you need a fresh
result *now* rather than waiting: deleting the specific stale
`PolicyReport` object (`kubectl delete policyreport <name> -n <ns>`) forces
Kyverno to regenerate it immediately — more reliable than restarting the
controllers, which was observed to *not* force an immediate rescan of
already-failing reports even though it clearly restarted the pods.

### `pod-security-restricted-host-controls`

**File:** [`kubernetes/policies/kyverno/pod-security-restricted-host-controls.yaml`](../../kubernetes/policies/kyverno/pod-security-restricted-host-controls.yaml)

**What's denied:** The remaining official Kubernetes Pod Security
Standards (restricted) controls not covered by `pod-security-restricted`:
(1) host namespaces (`hostNetwork`/`hostPID`/`hostIPC`), (2) `hostPath`
volumes, (3) `hostPort` on any container port, and (4) missing
`seccompProfile` (must be `RuntimeDefault` or `Localhost`).
`validationFailureAction: Enforce`.

**Why a separate policy, not more rules on `pod-security-restricted`:**
`validationFailureAction` is set at the policy level in Kyverno, not
per-rule. Adding new, unaudited rules to a policy already in `Enforce`
would put them live with zero audit period — exactly the risk the
Audit-first rollout process exists to avoid. Each new batch of PSS
controls gets its own policy so it can go through the same
Audit → fix → Enforce lifecycle independently.

**Scope:** `kube-system` excluded on all four rules, same reasoning as
`pod-security-restricted`. `node-exporter` (in `monitoring`, matched by a
`*node-exporter*` name pattern) is additionally excluded from
`disallow-host-namespaces`, `disallow-host-path`, and `disallow-host-ports`
specifically — it inherently needs `hostNetwork`/`hostPID` and
`hostPath` mounts (`/proc`, `/sys`, `/`) to read node-level metrics, and
because of `hostNetwork`, Kubernetes' own API server automatically
defaults `hostPort` to match `containerPort` on every container port
regardless of whether it's set explicitly — so a real `hostPort` value is
an unavoidable *consequence* of the `hostNetwork` requirement, not a
separate thing to fix. It is **not** exempted from `restrict-seccomp`,
since seccomp filtering doesn't conflict with host-metrics collection —
that one was fixed via Helm values instead (see below).

**Two real bugs caught during rollout, not just fixable violations:**
1. `disallow-host-ports` originally used the `X(hostPort): "null"` anchor
   (correct for `disallow-host-path`'s "must not exist" semantics, verified
   against Kyverno's own official policy), but incorrectly flagged
   `node-exporter`'s container even when `hostPort` was completely absent
   from the manifest. The correct anchor for "must be unset **or** zero" is
   `=(hostPort): 0` — a conditional anchor with an explicit expected value,
   not an existence anchor. Confirmed against Kyverno's official
   `disallow-host-ports` policy before fixing.
2. Fixing the pattern alone still left `node-exporter` failing, because the
   *live* `hostPort` value turned out to be `9100` (matching
   `containerPort`), not absent — the API server's `hostNetwork` defaulting
   behavior described above. This needed the exemption, not another
   pattern fix.

**Fixed via Helm values (not exempted):** `kube-prometheus-stack`'s
`node-exporter` (missing `seccompProfile`), the OTel Collector (missing
`seccompProfile`), and the `opa` sidecar in
`kubernetes/base/platform-api/opa-deployment.yaml` (missing
`seccompProfile`) — all three now set `seccompProfile.type: RuntimeDefault`
explicitly.

**How it's tested:**
1. Background-scan `PolicyReport`s confirmed every non-excluded workload
   passes all four rules after the fixes above.
2. Two isolated negative tests, since a single under-specified test pod
   gets caught by `pod-security-restricted` first and doesn't prove
   anything about *this* policy specifically: a pod satisfying every rule
   from the first policy but setting `hostNetwork: true` was rejected,
   correctly citing `disallow-host-namespaces` from this policy by name.

**Still needed for Phase 5** (spec §8's full "enforced everywhere" list):
default-deny NetworkPolicies (flagged as the highest-risk remaining item —
could break Prometheus scraping, Argo CD↔API-server traffic, or Kyverno's
own webhooks if not allowlisted correctly first), read-only root
filesystem, explicit resource requests/limits enforcement, immutable
digests / no mutable tags as an admission rule (not just signature
verification), namespace ownership labels + quotas, least-privilege RBAC
audit (no wildcard verbs/resources, no stray `cluster-admin` bindings
outside `break-glass-admin`), and documenting the CloudWatch audit log
retention period (control-plane logging itself was already enabled in an
earlier phase).
