# ADR-0002: Scope mandatory resource requests/limits to owned workloads

## Status
Accepted

## Context
Spec §8 originally required explicit CPU/memory requests/limits "everywhere."
Testing (2026-09-11) showed default chart pods for Argo CD, cert-manager,
external-secrets, kube-prometheus-stack, and Kyverno declare none. Adding a
`ResourceQuota` with CPU/memory dimensions to those namespaces caused new
pod admission to fail on the next rollout (`external-secrets` reproduced
live). Fixing this properly means overriding per-container Helm values
across ~19 containers in 5 charts, each with different footprints, with
real risk of misconfiguring a control-plane component (e.g. `argocd-repo-server`).

## Decision
Require explicit resource requests/limits, enforced via Kyverno and backed
by full `ResourceQuota` CPU/memory dimensions, only for workloads this
project authors (`platform-api`). Third-party chart namespaces keep
pod-count-only quotas; their `resources` block is whatever upstream ships.

## Consequences
- A runaway pod in `argocd`, `monitoring`, `cert-manager`, `external-secrets`,
  or `kyverno` can still exhaust node resources — quotas there only cap pod
  count, not consumption.
- If this becomes a real problem, the fix is per-chart Helm value overrides,
  done deliberately and tested one chart at a time — not a blanket policy.