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

## NetworkPolicies (Phase 5)

Unlike the entries above, these are plain Kubernetes `NetworkPolicy`
objects, not Kyverno `ClusterPolicy` resources — no admission engine
involved, enforced directly by the CNI.

### `default-deny-ingress` + `allow-intra-namespace` (`platform-api`)

**File:** [`kubernetes/base/platform-api/network-policy.yaml`](../../kubernetes/base/platform-api/network-policy.yaml)

**What's denied:** Any ingress connection into a pod in the `platform-api`
namespace that doesn't originate from another pod in that same namespace.
Egress is untouched — this is deliberately ingress-only, the first and
lowest-risk half of a full default-deny posture.

**Why ingress-only, and why one namespace first:** egress-deny would risk
breaking DNS, AWS API calls (Pod Identity), and every controller's
external dependencies (cert-manager↔ACME, ESO↔Secrets Manager, Argo
CD↔git/Helm repos) all at once. Ingress-only, scoped to one namespace we
fully control, gives real security value (nothing outside `platform-api`
can directly reach it or `opa`) with a much smaller blast radius. This is
the pilot for extending the same pattern to other namespaces later.

**Why two policies, not one:** an empty `podSelector` with no `ingress`
rules blocks *all* ingress into every pod in the namespace, including
pod-to-pod traffic *within* the same namespace. Since `platform-api` calls
`opa` over the network, a bare default-deny would have broken the app
immediately. `allow-intra-namespace` (an empty `podSelector` under `from`,
meaning "any pod in this namespace") adds that permission back —
NetworkPolicies are additive, so the two combine to: same-namespace
allowed, everything else denied.

**A real infrastructure gap this surfaced, not just a config task:**
`vpc-cni` (the VPC CNI) had never been Terraform-managed on this cluster
at all — it was running whatever unmanaged, default version and config
EKS bundled at cluster creation. `NETWORK_POLICY_ENFORCING_MODE=standard`
was present as an env var, but the actual master switch,
`ENABLE_NETWORK_POLICY`, was never set — meaning NetworkPolicy objects
were being silently accepted by the API server but never enforced at all.
Confirmed via the absence of any `PolicyEndpoint` objects (the VPC CNI
network-policy controller's internal representation of a compiled
policy). Fixed by bringing `vpc-cni` under Terraform for the first time as
a proper `aws_eks_addon` (see
[`terraform/modules/aws-eks/addons.tf`](../../terraform/modules/aws-eks/addons.tf)),
pinned to the exact version already running so only the network-policy
config changed, with `configuration_values` explicitly setting
`enableNetworkPolicy: true`.

**Also learned:** the VPC CNI's eBPF-based enforcement is not retroactive
— pods running before a policy exists (or before the feature itself was
enabled) don't get enforcement attached until they're recreated. `opa`
needed two separate restarts during this rollout: once when the policy
was first created, and again after the `vpc-cni` addon change actually
turned enforcement on, since the first restart happened before the
feature was really active.

**Side discovery, fixed separately:** testing this required restarting
`platform-api`, which revealed its running image predated cosign signing
(from phase 7) and had no valid signature — meaning it could not be
restarted, rescheduled, or survive a node failure at all under
`require-cosign-signature`'s enforcement. Fixed by updating
`kubernetes/base/platform-api/deployment.yaml` to a current, verified,
signed digest. This is a symptom of the still-open phase 8 gap:
`platform-api` isn't Argo CD-managed, so nothing has been redeploying it
with fresh, signed images since CI started signing.

**How it's tested:**
1. Same-namespace request (`platform-api`'s own namespace → `opa:8181`)
   succeeds (`HTTP_STATUS:200`).
2. Cross-namespace request (`default` namespace →
   `opa.platform-api.svc.cluster.local:8181`) times out
   (`HTTP_STATUS:000`, curl exit 28) — a real connection-level block, not
   an application-level rejection.
3. Confirmed via `kubectl get policyendpoints -n platform-api` that both
   policies actually compiled into enforced endpoints, not just accepted
   API objects.

**Still needed for Phase 5** (spec §8's full "enforced everywhere" list):
extending default-deny to the remaining namespaces (higher risk — will
need explicit allow rules for Prometheus scraping, Argo CD↔API-server
traffic, and Kyverno's own webhook calls before it's safe to turn on
elsewhere), egress-deny (deferred entirely for now), immutable digests /
no mutable tags as an admission rule (not just signature verification),
namespace ownership labels + quotas, and least-privilege RBAC audit (no
wildcard verbs/resources, no stray `cluster-admin` bindings outside
`break-glass-admin`).

**CloudWatch audit log retention: done.** The EKS control-plane log group
(`/aws/eks/dev/cluster`) was created implicitly by AWS when control-plane
logging was enabled in an earlier phase, but was never brought under
Terraform and had no retention policy — CloudWatch's default is "never
expire," a real unbounded-cost gap (it had already accumulated ~1.45GB).
Fixed via a declarative `import` block (Terraform 1.5+; the root-module
restriction on `import` blocks means the block itself lives in
`terraform/environments/dev/aws/imports.tf` even though the resource it
targets is defined inside the `aws-eks` module) plus a new
`aws_cloudwatch_log_group` resource setting `retention_in_days = 30`,
matching the existing VPC flow logs retention for consistency. The import
correctly adopted the existing log group and its accumulated history in
place — the apply was `0 added, 1 changed, 0 destroyed`, not a
destroy-and-recreate that would have lost the existing audit trail.

### `require-resource-hardening`

**File:** [`kubernetes/policies/kyverno/require-resource-hardening.yaml`](../../kubernetes/policies/kyverno/require-resource-hardening.yaml)

**What's denied:** Any `Pod` in the `platform-api` namespace whose
container doesn't set `readOnlyRootFilesystem: true`, or doesn't set
explicit `resources.requests` (cpu and memory) plus a `resources.limits`
CPU value. `validationFailureAction: Enforce`.

**Why CPU limit but not memory limit:** a real, deliberate scoping
decision, not spec's literal wording. Memory limits carry genuine
operational risk on GC-heavy workloads (Go, Java) — a limit set even
slightly too conservative causes unpredictable OOM-kills under load, which
is a worse failure mode than "no ceiling exists." CPU limits are much
lower-risk to require broadly: the worst case is throttling (a
performance hit), not a crash. Requests are required unconditionally for
both, since the scheduler needs them for bin-packing regardless.

**Why scoped to `platform-api` only, not cluster-wide:** see the matching
tradeoff entry in `docs/acceptance-checklist.md` for the full reasoning —
in short, every third-party chart installed so far fails this policy, and
fixing all of them (particularly Argo CD, whose chart sets *no* resource
configuration at all and isn't GitOps-managed) is real, uneven work with
a secondary security payoff compared to what's already enforced on those
same components. `match` targets the `platform-api` namespace directly
rather than excluding everything else — cleaner than maintaining a
growing exclude-list as more namespaces get added to the cluster.

**How it's tested:**
1. Background-scan `PolicyReport`s confirmed `platform-api` and `opa`
   both pass cleanly after `opa` was updated to set
   `readOnlyRootFilesystem: true` (verified functionally, not just that
   the pod started — a live request through it still returned `200` after
   the change, confirming OPA doesn't need writable root for this
   invocation).
2. A test pod satisfying every other policy enforced tonight (non-root,
   no privilege escalation, dropped capabilities) but with no resource
   configuration and a writable root filesystem was rejected, correctly
   citing both `require-readonly-rootfs` and
   `require-resource-requests-limits` by name.

### `require-immutable-image-digest`

**File:** [`kubernetes/policies/kyverno/require-immutable-image-digest.yaml`](../../kubernetes/policies/kyverno/require-immutable-image-digest.yaml)

**What's denied:** Any `Pod` in the `platform-api` namespace whose
container image is referenced by tag rather than digest (`@sha256:...`).
`validationFailureAction: Enforce`.

**Why scoped to `platform-api` only:** same reasoning as
`require-resource-hardening`, and even more clear-cut here — every
third-party Helm chart installed tonight (Argo CD, Kyverno, cert-manager,
External Secrets Operator, kube-prometheus-stack, the OTel Collector)
references its images by semantic-version tag, not digest, as standard
practice for tracking upstream releases. Enforcing digest-only cluster-wide
would break all seven services immediately, not just some of them.

**Real violation found and fixed, not exempted:** `opa`'s manifest
referenced `openpolicyagent/opa:1.4.2` (a tag) despite `platform-api`
itself already being digest-pinned. Fixed by resolving the exact digest
already running (`kubectl get pod ... -o
jsonpath='{.status.containerStatuses[0].imageID}'`, rather than querying
Docker Hub separately, to guarantee the pinned digest matches what was
actually verified running) and updating
`kubernetes/base/platform-api/opa-deployment.yaml` to reference it
directly.

**How it's tested:**
1. Background-scan confirmed `opa`'s live pod reached `0 FAIL` after the
   digest fix.
2. A test pod satisfying every other policy enforced tonight (non-root,
   no privilege escalation, dropped capabilities, read-only root,
   resource requests/limits) but referencing `alpine:latest` by tag was
   rejected, correctly citing only `require-image-digest` — confirming
   isolation from the other rules, not just that *something* got blocked.

### `require-namespace-labels`

**File:** [`kubernetes/policies/kyverno/require-namespace-labels.yaml`](../../kubernetes/policies/kyverno/require-namespace-labels.yaml)

**What's denied:** Creating or updating any `Namespace` without both an
`owner` and an `environment` label, except the built-in
`kube-system`/`kube-public`/`kube-node-lease`/`default` namespaces.
`validationFailureAction: Enforce`.

**A different resource scope than every other policy tonight:**
`Namespace` is cluster-scoped, not namespaced, so Kyverno reports on it
via `ClusterPolicyReport`, not the namespaced `PolicyReport` every other
policy in this catalog uses. Worth remembering — checking the wrong report
type looks identical to "nothing has been scanned yet."

**How it's tested:**
1. Every existing namespace this project created (`argocd`,
   `cert-manager`, `external-secrets`, `kyverno`, `monitoring`,
   `observability`, `platform-api`) was labeled with `owner=platform-team
   environment=dev` and confirmed clean via `ClusterPolicyReport` before
   enforcement was turned on.
2. `kubectl create namespace unlabeled-test` (no labels) was rejected
   outright by the admission webhook, correctly citing this rule.

**Paired with a plain `ResourceQuota`** on `platform-api`
([`kubernetes/base/platform-api/resource-quota.yaml`](../../kubernetes/base/platform-api/resource-quota.yaml))
— not a Kyverno policy, a native Kubernetes object, enforced directly by
the API server. Caps the namespace's *total* resource consumption (not
per-pod), sized generously at roughly 3x current usage (`pods: 10`,
`requests.cpu: 500m`, `requests.memory: 512Mi`, `limits.cpu: 1`) so it's a
genuine safety ceiling against runaway growth — a bug or misconfiguration
consuming unbounded resources in one namespace — rather than something
that constrains normal operation. Scoped to `platform-api` only, same
reasoning as the other platform-api-scoped policies: no established
usage baseline exists yet for the third-party charts to size a sensible
quota against.

## RBAC least-privilege audit (Phase 5)

Spec §8 requires "no wildcard verbs/resources in ClusterRoles, no
`cluster-admin` bindings outside a documented, logged break-glass
identity." This is an audit, not a Kyverno policy — no enforcement
mechanism was added, since blocking wildcard `ClusterRole` creation
outright would break every operator-pattern chart in this cluster (Argo
CD and the Prometheus Operator both structurally require broad
permissions to manage arbitrary resources on behalf of what they deploy).

**Findings:**
- Every wildcard `ClusterRole` found (`argocd-application-controller`,
  `argocd-server`, `kube-prometheus-stack-operator`, plus AWS/Kubernetes
  system roles) is either system-managed or an inherent requirement of a
  legitimate operator pattern — no evidence of anything we configured
  ourselves being over-privileged.
- Both existing `cluster-admin` `ClusterRoleBinding`s
  (`system:masters`→`cluster-admin`, `eks:addon-manager`→
  `eks:addon-cluster-admin`) are Kubernetes/AWS-foundational, not
  something granted by this project.
- **Real gap found:** checking EKS access entries directly
  (`aws eks list-access-entries`) showed only `platform-admin` (the
  everyday SSO admin identity) had Kubernetes-level cluster access —
  `break-glass-admin`, the identity actually *named* and intended for
  emergency access, had none. Every routine `kubectl` command and a
  genuine incident response would have been indistinguishable in the
  audit trail, since they'd be the same principal. This is the opposite
  problem from what spec's wording warns about.

**Fix:** added `break-glass-admin`'s role ARN to `cluster_admin_principal_arns`
in [`terraform/environments/dev/aws/main.tf`](../../terraform/environments/dev/aws/main.tf),
granting it a proper EKS access entry alongside `platform-admin`.
Confirmed via `aws eks list-access-entries` after apply.

**A related identity clarified during this fix, not a second gap:**
`break-glass-dev` (an IAM user predating `break-glass-admin`, referenced
in this doc's earlier MFA tradeoff entry) has no direct permissions of its
own — its only inline policy (`AssumeBreakGlassAdmin`) lets it
`sts:AssumeRole` into `break-glass-admin`. It's the intended low-privilege,
MFA-gated entry point a human authenticates as before assuming the
privileged role; the acting principal for any subsequent API or `kubectl`
call becomes the assumed role, not the user. It doesn't need its own EKS
access entry — granting the entry to the role it assumes into was the
correct target, not a workaround.

**Not covered by this audit** (spec's wording is specifically about
`ClusterRole`s and `cluster-admin` bindings): namespaced `Role`s and
`RoleBinding`s were not comprehensively reviewed. Worth a pass before
calling this project interview-ready, particularly for anything the
Argo CD or Prometheus Operator charts create with elevated namespaced
permissions.
