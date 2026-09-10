# ADR-0001: Accept wildcard RBAC in third-party Helm chart defaults

## Status
Accepted

## Context
Spec §8 requires least-privilege Kubernetes RBAC: "no wildcard verbs/resources
in ClusterRoles, no `cluster-admin` bindings outside a documented, logged
break-glass identity."

A live audit of `ClusterRole` objects (2026-09-11) found three roles with
wildcard verbs and/or resources, none of which were created by this project's
own manifests — all three are default `ClusterRole` objects shipped by
upstream Helm charts:

- `argocd-application-controller` — `apiGroups: ["*"]`, `resources: ["*"]`,
  `verbs: ["*"]`, plus `nonResourceURLs: ["*"]` with `verbs: ["*"]`.
- `argocd-server` — `apiGroups: ["*"]`, `resources: ["*"]`, verbs limited to
  `[delete, get, patch]`.
- `kube-prometheus-stack-operator` — wildcard verbs scoped to its own
  `monitoring.coreos.com` CRDs, plus `configmaps`/`secrets` and
  `statefulsets`.

Argo CD's application-controller needs this breadth by design: as a GitOps
controller, it must be able to create, update, and delete arbitrary resource
kinds across the cluster, because it has no way to know ahead of time which
CRDs or built-in types a given Git-tracked manifest will use. The
Prometheus operator similarly needs to manage its own CRDs and the
configmaps/secrets/statefulsets it generates from them. Hand-restricting
either role would mean forking and maintaining a patched copy of each
chart's RBAC indefinitely, fighting every future upstream chart upgrade,
in exchange for protection against a threat (arbitrary future resource
types) that is exactly what these two controllers are supposed to be able
to act on.

## Decision
Accept these three wildcard `ClusterRole` objects as a documented exception
to the least-privilege requirement, rather than patching or replacing them.
Do not treat this ADR as blanket permission for *new* wildcard roles —
any custom (non-chart-default) `ClusterRole` this project writes going
forward must still avoid `"*"` verbs/resources; this exception is scoped
specifically to the two named charts above, as installed.

Compensating controls already in place that keep the residual risk bounded:

- **Blast radius is scoped by identity, not by RBAC alone.** These
  ClusterRoles bind only to each chart's own ServiceAccount — not to any
  human or CI identity — so exploiting this privilege requires first
  compromising the `argocd-application-controller` or
  `kube-prometheus-stack-operator` pod itself.
- **Cluster-admin for humans is separately restricted** (see
  `terraform/environments/dev/aws/main.tf`, `cluster_admin_principal_arns`)
  to exactly two named IAM principals: the `platform-admin` SSO role and a
  dedicated `break-glass-admin` role. This ADR does not change that.
- **Kyverno's `pod-security-restricted` and `require-resource-hardening`
  policies** still constrain what these pods themselves can run as
  (non-root, no privilege escalation, dropped capabilities, seccomp), even
  though they can act broadly on the API once running.
- **API server and audit logs ship to CloudWatch** with 30-day retention
  (`terraform/modules/aws-eks/logging.tf`), so any anomalous use of these
  service accounts' broad permissions is logged and reviewable.
- **NetworkPolicy default-deny** is applied to the `argocd` and `monitoring`
  namespaces, limiting network-level lateral movement even if a pod in
  either namespace were compromised.

## Consequences
- A compromise of the `argocd-application-controller` or
  `kube-prometheus-stack-operator` pod is equivalent to a cluster-admin
  compromise from an RBAC perspective. This is treated as an accepted risk
  of running these tools as-is, not as an oversight.
- Any future chart upgrade that changes these RBAC rules should be reviewed
  for scope creep, not rubber-stamped — this ADR documents the *current*
  shape of the exception, not an open-ended allowance.
- If a future phase introduces a stricter multi-tenancy requirement (e.g.
  running untrusted workloads alongside these controllers), this decision
  should be revisited — likely via Argo CD's app-of-apps + project-scoped
  RBAC feature, which can narrow `argocd-application-controller`'s reach
  per-`AppProject` instead of cluster-wide.