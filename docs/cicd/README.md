# CI/CD and GitOps workflow guide

How a change moves from a pull request to a running workload in the cluster.

## CI: GitHub Actions (`.github/workflows/ci.yaml`)

Runs on every push/PR to `main`. Three jobs:

1. **`terraform`** — `terraform fmt -check -recursive` and `terraform
   validate` (backend-less init, no state access needed for validation).
2. **`go`** — `go build ./...` and `go test ./...` for `platform-api`.
3. **`build-and-push`** — only runs on `main` (not PRs), only after both
   jobs above pass:
   - Assumes `github-actions-platform-api` via OIDC (no static AWS keys).
   - Builds the image, tagged with `github.sha`.
   - **Trivy scan** for CRITICAL/HIGH vulnerabilities — `exit-code: 1`,
     so a vulnerable image never reaches ECR.
   - Pushes to ECR only after the scan passes.
   - Generates an SBOM (`sbom.spdx.json`, SPDX format) and uploads it as
     a workflow artifact.
   - Installs cosign and **signs the image by digest**, keyless (OIDC
     identity tied to this exact workflow file + `refs/heads/main`,
     verified later by Kyverno's `require-cosign-signature`).

**Known gap:** nothing in this workflow updates
`kubernetes/base/platform-api/deployment.yaml` with the new digest.
Signing an image does not deploy it — see "The manual step" below.

## CD: Argo CD (GitOps, pull-based)

Argo CD does not receive pushes from CI. It polls this repository
(default ~3 min, or a webhook) and continuously reconciles live cluster
state against what's declared in Git.

**App-of-apps pattern:**
- [`kubernetes/argocd/root-app.yaml`](../../kubernetes/argocd/root-app.yaml)
  — one Application watching `kubernetes/argocd/apps/`.
- One file per component in that directory
  (`platform-api.yaml`, `kyverno.yaml`, `network-policies.yaml`,
  `resource-quotas.yaml`, etc.) — each its own Argo CD `Application`,
  pointing either at a Helm chart or a raw-manifest path in this repo.
- `root`'s own `syncPolicy.automated` picks up any new file dropped into
  `apps/` automatically — every Application added this project (including
  `platform-api`'s, added after the fact once we noticed it had been
  running from a manual `kubectl apply` outside GitOps entirely) required
  no change to `root` itself.
- Every Application sets `syncPolicy.automated: {prune: true, selfHeal:
  true}` — manual drift (someone hand-edits a live object) gets reverted
  automatically, and objects removed from Git get deleted from the
  cluster, not just orphaned.

## The manual step (by design, not an oversight)

Today, deploying a new `platform-api` build is:
1. CI builds, scans, signs — fully automatic on every merge to `main`.
2. A human resolves the new image's digest and edits
   `kubernetes/base/platform-api/deployment.yaml` to reference it.
3. Argo CD picks up that Git change and rolls it out automatically —
   this half is fully automatic.

Closing step 2 (an image-updater or a CI commit-back job) is possible but
was deliberately deferred: a CI job that pushes to `main` needs explicit
loop-prevention (that push would otherwise re-trigger `build-and-push`
against a new commit SHA, building yet another image, ad infinitum), and
"a human approves the exact digest that reaches production" is itself a
legitimate, common change-control pattern — not automatically a gap to
close.

## The enforcement point that actually matters

Kyverno's `require-cosign-signature` (see
[policy catalog](../policy-catalog/README.md)) is what makes any of this
matter operationally: a pod cannot run in `platform-api` unless its image
carries a valid cosign signature tied to this exact GitHub Actions
workflow. CI and Argo CD are the delivery mechanism; this policy is the
actual security boundary.
