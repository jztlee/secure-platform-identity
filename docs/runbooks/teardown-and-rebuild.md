# Environment teardown and rebuild

Purpose: tear down the dev AWS environment to stop cost accrual between
active work periods (e.g. between build phases, or before/after an
interview), and bring it back up reliably without re-discovering the
gotchas from scratch.

Current monthly cost driver: EKS control plane + node group + NAT
gateways (VPC). See AWS Billing > Bills for the current estimate.

## What Terraform destroys vs. what survives

Destroyed (all in `terraform/environments/dev/aws`, workspace
`aws-dev-foundation`): VPC/networking, EKS cluster + node group, ECR
repository (and its images), CloudTrail, Config, GuardDuty, Security Hub,
Inspector, Access Analyzer, the environment KMS key. Everything running
*inside* the cluster (Argo CD, Kyverno, cert-manager, platform-api, etc.)
disappears automatically with it — no separate cleanup needed there.

Survives, untouched: the bootstrap OIDC trust workspace
(`terraform/bootstrap/aws-oidc-trust` — GitHub Actions role,
break-glass-admin), SSO/Identity Center access, and all code + HCP
Terraform state/history.

## Teardown

1. Confirm the three force-delete/force-destroy flags are present
   (`terraform/modules/aws-ecr/main.tf`, `terraform/modules/aws-security/cloudtrail.tf`,
   `terraform/modules/aws-security/config.tf`) — without them, `destroy`
   fails on the non-empty ECR repo and S3 log buckets.
2. From `terraform/environments/dev/aws`, run `terraform destroy`.
   **Read the full plan before approving** — this is the most
   irreversible command in the project.

## Rebuild

1. `terraform apply` from `terraform/environments/dev/aws` — recreates
   VPC, EKS, ECR, security baseline.
2. **Update the EKS API allowlist first if your IP has changed** —
   `allowed_cidrs` in `terraform/environments/dev/aws/main.tf` is locked
   to a single IP; `kubectl` will fail with a network-level error against
   the wrong one. Check with `curl ifconfig.me`.
3. `aws eks update-kubeconfig --name dev --region us-east-1 --profile platform-admin`
4. Watch for the `AWS_PROFILE` shadowing gotcha: if `AWS_ACCESS_KEY_ID` /
   `AWS_SECRET_ACCESS_KEY` / `AWS_SESSION_TOKEN` are exported in the
   shell (e.g. left over from a bootstrap-operator session), they
   silently override `AWS_PROFILE` and `kubectl` will auth as the wrong
   identity with `Unauthorized`. `unset` them if so.
5. Bootstrap Argo CD manually (not Terraform-managed, see ADR/tradeoff
   note): `helm repo add argo https://argoproj.github.io/argo-helm`,
   `helm install argocd argo/argo-cd -n argocd --create-namespace --version 10.8.4`.
6. `kubectl apply -f kubernetes/argocd/root-app.yaml` once — everything
   else syncs from git automatically from here.
7. **Manually re-install the Kyverno CRDs** — the chart is configured
   with `crds.install: false` because `clusterpolicies.kyverno.io` and
   `policies.kyverno.io` exceed the 256KB Kubernetes annotation limit
   under every Argo CD apply/diff strategy we tried. Without this step,
   `kyverno-admission-controller` crash-loops on a missing-CRD sanity
   check:
   ```bash
   helm repo add kyverno https://kyverno.github.io/kyverno/
   helm template kyverno kyverno/kyverno --version 3.9.0 --namespace kyverno \
     | kubectl apply --server-side --force-conflicts -f -
   ```
8. Verify: `kubectl get applications -n argocd` (all `Synced`/`Healthy`),
   `kubectl get pods -n kyverno` (4 controllers `Running`, no
   `CrashLoopBackOff`).
