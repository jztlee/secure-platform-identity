# Study guide

A self-test / interview-prep reference for this project, in Q&A form —
same idea as the checkpoint questions asked after each build step. Cover
the answer, quiz yourself, then check. Organized by topic, not phase (like
the glossary), since some topics (IAM scoping, bootstrap credentials)
recur across phases.

Update this alongside `acceptance-checklist.md` and `glossary.md` at the
end of each phase — it's most useful if it grows with the project instead
of being written once at the end.

*Last updated: through the account-level hardening trio (Phase 3).*

---

## HCP Terraform & workspace architecture

**Q: Why does this project use multiple HCP Terraform workspaces instead of one big workspace for everything?**
A: Each workspace is a separate, independently reviewable plan/apply boundary with its own state and its own scoped credentials. Splitting by concern (bootstrap trust, dev networking, dev EKS, etc.) means a bad change in one area has a limited blast radius, and each plan is small enough to actually review before approving.

**Q: What's the difference between a VCS-driven, CLI-driven, and API-driven workspace?**
A: VCS-driven runs automatically when the connected repo/branch changes (via a webhook or GitHub App). CLI-driven only runs when a human executes `terraform plan`/`apply` from their own machine. API-driven is triggered programmatically. `aws-dev-foundation` is VCS-driven; `bootstrap-aws-trust` is deliberately CLI-driven (see next section for why).

**Q: What are HCP Terraform's three workflow-scoping concepts, and what does each control?**
A: Organization (top-level account), Project (groups workspaces — this project uses `bootstrap`, `shared-platform`, `nonproduction`, `production`), and Workspace (the actual plan/apply/state boundary, one per environment or concern).

---

## Phase 1 & 2: repo setup and OIDC bootstrap trust

**Q: Why does `terraform/bootstrap/aws-oidc-trust/versions.tf` use a `cloud { organization = ..., workspaces { name = ... } }` block instead of a traditional S3+DynamoDB remote state backend?**
A: The `cloud` block ties this configuration directly to a specific HCP Terraform workspace, which gives remote execution, state locking, and policy-set enforcement out of the box — no separate state-storage infrastructure to bootstrap and secure first. (It also sidesteps a smaller chicken-and-egg problem: standing up an S3 bucket + DynamoDB table for state would itself need to be applied from somewhere.)

**Q: Why pin provider versions with `~> 6.60` (the "pessimistic operator") instead of leaving them unconstrained?**
A: `~>` allows patch/minor updates within that major version but blocks an unexpected breaking major-version upgrade from silently changing behavior on the next `terraform init`. Combined with the committed `.terraform.lock.hcl`, this makes provider versions reproducible across machines and time.

**Q: What does the `aws_iam_openid_connect_provider` resource in `oidc-provider.tf` actually establish?**
A: It registers HCP Terraform's OIDC issuer (`https://app.terraform.io`) as a trusted external identity provider inside AWS IAM — the prerequisite that lets any IAM role's trust policy reference it as a `Federated` principal later. Without this resource existing first, no role could ever trust an HCP Terraform-issued token.

**Q: Why does the OIDC provider need a certificate thumbprint (`thumbprint_list`), and why is it fetched via `data "tls_certificate"` instead of hardcoded?**
A: The thumbprint is the SHA1 fingerprint of the issuer's TLS certificate, historically used to verify the OIDC endpoint's authenticity. Fetching it dynamically via the `tls_certificate` data source means Terraform always reads the certificate's *current* fingerprint at plan/apply time — if HCP Terraform ever rotated their TLS cert, a hardcoded value would go stale and silently be wrong.

**Q: What is `client_id_list = ["aws.workload.identity"]` for, and where else does that exact string matter?**
A: It's the audience (`aud`) claim value AWS will accept in incoming OIDC tokens. It has to match exactly what HCP Terraform puts in the tokens it issues, and it's the same value checked in the `StringEquals` condition on `app.terraform.io:aud` inside the role's trust policy (`iam-roles.tf`) — the OIDC provider registration and the trust policy condition have to agree, or authentication fails.

**Q: What branch protection is actually configured on `main`, and how is it implemented?**
A: A GitHub **ruleset** named `main-protection` (the newer replacement for classic branch protection rules), Active, targeting `main`, with three rules enabled: **Restrict deletions**, **Require a pull request before merging**, and **Block force pushes**. Everything else (required approval count, required status checks, signed commits, linear history, code scanning) is currently off.

**Q: Why does the ruleset have an empty bypass list, and why does that matter?**
A: The bypass list is where you'd exempt specific roles/users/apps from the rule. Leaving it empty means the rule applies to *everyone*, including the repo owner — a rule that exempts its own owner isn't really enforced, it's just a suggestion. An empty bypass list is what makes "protected branch" actually mean something.

**Q: What does each of the three enabled rules concretely prevent?**
A: **Restrict deletions** stops `main` itself from being deleted (accidentally or otherwise) by anyone without bypass permission. **Require a pull request before merging** stops direct pushes to `main` — every change has to go through a PR, which is what makes the whole feature-branch workflow used throughout this project actually mandatory rather than just a convention. **Block force pushes** stops anyone from rewriting `main`'s history (e.g., `git push --force`), which would otherwise let someone silently erase or alter past commits.

**Q: "Require a pull request before merging" is on, but there's no required minimum reviewer count. Is that a gap?**
A: For a solo project, no — there's only one contributor, so requiring a second approver isn't meaningful yet. It's worth flagging as something to revisit if this repo ever gets a second contributor, or explicitly calling out in an ADR as a deliberate solo-project simplification rather than an oversight.

**Q: Why isn't "Require status checks to pass" enabled yet, even though the spec calls for CI gating?**
A: Because there's no CI pipeline yet to produce a status check to require — that's Phase 7. Enabling this rule now would either do nothing (no check exists to reference) or block all merges outright (waiting on a check that never reports). It'll make sense to turn on once GitHub Actions exists and reports status checks that PRs can point at.

---

## The bootstrap chicken-and-egg problem

**Q: Why can't `terraform/bootstrap/aws-oidc-trust` authenticate to AWS the same way `aws-dev-foundation` does (OIDC, no static credentials)?**
A: OIDC federation only works because an IAM OIDC identity provider and a trust policy already exist in AWS, trusting HCP Terraform's tokens. Bootstrap's whole job is to *create* that OIDC provider and the roles that trust it. Nothing can authenticate via a trust relationship that doesn't exist yet — so *something* has to hold a real AWS credential to do that first creation. That's unavoidable; the question is just what kind of credential and how it's protected.

**Q: Why can't the `aws-dev-foundation` workspace just manage its own IAM role's permissions (i.e., why does `iam-roles.tf` have to live in bootstrap, not in the dev-foundation workspace)?**
A: If a workspace could edit the IAM policy attached to the role it itself assumes, that's a self-grant loop: anyone who can merge a PR to `main` could add `"iam:*"` or `"*"` to that role's own policy, and the next auto-apply would grant the automated pipeline full account access — with no human touching AWS credentials at any point. Keeping permission-granting Terraform (bootstrap) in a separate, human-gated workspace from workload Terraform (dev-foundation) means a compromised or careless PR to routine infrastructure can't escalate into full account takeover.

**Q: What would a real enterprise do differently for this bootstrap problem?**
A: They wouldn't bootstrap a single workload account from zero at all. In a full AWS Organizations setup, trust is established once, centrally, at the *management* account (via the tightly-controlled root user or Control Tower automation). Every subsequently created account (via Account Factory) automatically inherits a cross-account trust role from the management account, so it never needs its own bare credential. This project only builds a single `dev` workload account (§2 scope call) — there's no pre-existing management account to inherit trust from, so the bootstrap problem has to be solved locally instead of for free.

**Q: Why is `aws-dev-foundation`'s IAM policy split into narrow action lists (create/delete explicitly scoped) plus separate `Describe*`/`Get*`/`List*` "read" statements, rather than one broad policy?**
A: Every gap hit during iterative development was a read-only verification action, never a mutating one — so create/delete/modify actions stay explicitly enumerated (tightly scoped), while read verbs are wildcarded to reduce the temp-credential debugging cycle. This is a documented, accepted tradeoff (see `acceptance-checklist.md`), not an oversight — the alternative is enumerating every single read action ever used, verified against CloudTrail history.

---

## Bootstrap operator credentials (MFA + short-lived STS)

**Q: Why not just use a permanent IAM user with long-lived access keys for bootstrap, and leave it that way?**
A: Static, long-lived keys don't expire on their own — if one leaks (accidentally committed, exposed in a chat, phished), it stays usable indefinitely until someone notices and manually revokes it. This directly conflicts with the project's own acceptance criterion: "no static cloud credentials anywhere."

**Q: What's the actual setup used instead, and why does it solve both the security problem *and* the "recreating credentials every time" friction problem?**
A: A permanent IAM user (`bootstrap-operator`) exists once — solving the recreation friction — but its IAM policy requires `aws:MultiFactorAuthPresent: true` on every meaningful action except `sts:GetSessionToken`. So the user's raw long-term access key, used directly, can do almost nothing. Each working session, you run `aws sts get-session-token` with an MFA code to mint temporary credentials (default 12-hour expiry) that *do* carry the MFA-present flag. The long-lived secret is protected by something an attacker can't steal remotely (your physical MFA device); what actually gets used day-to-day expires on its own.

**Q: In that setup, why is `sts:GetSessionToken` allowed *without* the MFA condition, when everything else requires it?**
A: You need to call `GetSessionToken` in order to *obtain* an MFA-authenticated session in the first place — if it also required MFA-present, there'd be no way to bootstrap the very first authenticated call. It's the one deliberate exception, and it can't do anything by itself except return temporary credentials tied to the same permission boundary.

**Q: Why is this MFA+STS pattern described as "a right-sized stand-in for the management account's root user," not a compromise?**
A: In a real org, the management account's root user is the single, rarely-touched, MFA-protected credential everything else bootstraps from. This project has no management account to inherit trust from, so the same shape of control — rare use, hardware/app-based MFA required, short-lived resulting credentials — gets applied directly to the one account that exists, at a smaller scale.

---

## AWS networking (Phase 3)

**Q: What's the difference between the public, private-app, and private-data subnet tiers, and why three instead of one flat network?**
A: Public subnets hold internet-facing resources (ALB, NAT gateways) with a route to an Internet Gateway. Private-app subnets hold compute (EKS nodes) with no direct internet route — outbound-only via NAT. Private-data subnets are reserved for data stores, with the tightest reachability. Segmenting means a compromised app-tier workload doesn't have a direct network path to data-tier resources by default.

**Q: What do VPC endpoints do, and why does this project have them for S3, ECR, STS, Secrets Manager, and CloudWatch Logs specifically?**
A: A VPC endpoint lets resources in private subnets reach specific AWS services over AWS's internal network instead of routing out through a NAT gateway to the public internet. Those five services are exactly what a private EKS cluster's control plane and workloads need routinely (pulling images from ECR, reading/writing CloudWatch logs, authenticating via STS, reading secrets, and S3 for various artifacts) — keeping that traffic off the public internet path entirely, and off the NAT gateway's per-GB charge.

**Q: What does VPC flow logging capture, and why send it to CloudWatch rather than nowhere?**
A: Metadata about IP traffic crossing network interfaces in the VPC (source/destination, port, protocol, accept/reject, byte counts — not packet contents). It's the forensic record for "what talked to what" during an incident investigation, and a feed for anomaly-detection tooling later (GuardDuty uses VPC Flow Logs as one of its data sources).

---

## Account-level hardening trio

**Q: What does S3 Block Public Access (account-level) actually do, precisely?**
A: It's an account-wide guardrail that overrides any individual bucket's policy or ACL — no bucket, present or future, can be made publicly accessible, regardless of what that bucket's own configuration says. It's not a network control (it doesn't filter traffic); it's a veto on a specific class of access-control misconfiguration.

**Q: Why put that guardrail at the account level instead of just being careful to configure each bucket correctly?**
A: Per-bucket discipline eventually fails — someone forgets, a new bucket gets created without thinking, a policy gets copy-pasted wrong. The account-level setting doesn't rely on remembering; it makes "publicly accessible" impossible regardless of future mistakes, including on buckets that don't exist yet.

**Q: What does EBS encryption-by-default do, and what's the one important limitation?**
A: Every *new* EBS volume created in the region gets encrypted automatically, with no need for whatever creates it (a person, a Terraform module, Karpenter provisioning EKS nodes later) to remember to ask for encryption. The limitation: it's forward-looking only — it does not retroactively encrypt volumes that already existed before the setting was turned on.

**Q: Why is EBS encryption-by-default scoped per-region rather than account-wide like S3 Block Public Access?**
A: Because that's how AWS's own API for it is shaped — `EnableEbsEncryptionByDefault` is inherently a per-region setting, not an account-wide one. The IAM permission for it is `Resource = "*"` not because of a scoping shortcut, but because AWS provides no narrower resource type for this specific action.

**Q: What problem does requiring IMDSv2 actually solve, in concrete terms?**
A: Every EC2 instance can query a special internal address to get its own temporary AWS credentials — that's necessary and normal. IMDSv1 lets that query happen with no proof of intent, so if an attacker finds an unrelated bug in an app running on the instance (SSRF — tricking the app into fetching an attacker-chosen URL), they can redirect that fetch at the metadata address and steal the instance's live AWS credentials. This is exactly the mechanism behind the 2019 Capital One breach. IMDSv2 requires a `PUT`-for-a-token step before any credential can be read — a two-step handshake that most SSRF techniques can't replicate, since they can usually only force a simple `GET`.

**Q: How is IMDSv2 different from S3 Block Public Access, conceptually — they're both "account-wide guardrails," so what's the actual distinction?**
A: S3 Block Public Access stops a *storage resource* from being misconfigured into public exposure. IMDSv2 stops an *attacker who already has a foothold in an app* from stealing that server's own AWS credentials and using them to pivot elsewhere (potentially including S3, EC2, anything that role can touch). One protects a specific resource type from misconfiguration; the other protects the credential-issuance mechanism itself from being abused by an attacker who's already partially in.

**Q: Why apply the permission for each of these three settings to the bootstrap-managed IAM role via a separate `terraform apply` in bootstrap, then apply the actual resource via a normal PR merge into `aws-dev-foundation` — why not do it all in one step?**
A: Same reason as the general bootstrap/workload split: granting a *new kind of permission* to the automated pipeline's role is a privilege-granting action, so it goes through the human-gated bootstrap workspace first. Once the permission exists, actually *using* it to create the resource is routine infrastructure work, so it flows through the normal reviewed-PR-into-VCS-driven-workspace path.

---

## Project scope decisions

**Q: Why does this project build only one real AWS account (`dev`) instead of the full multi-account Organizations model (management, security, log-archive, shared-services, dev/staging/prod)?**
A: Building and fully wiring up seven accounts' worth of cross-account trust, SCPs, and centralized logging would cost weeks without deepening the actual target skills (Kubernetes, Go, zero-trust identity) — this project is AWS-first and Kubernetes/Go-from-zero at the same time. The full model is documented as target state in `docs/`, which is itself a legitimate, defensible interview answer: "here's the target architecture and why I scoped down for this build."

**Q: Is `aws-prod-foundation`/`aws-prod-eks` real infrastructure, or just configuration?**
A: Per the spec's Non-goals ("no production cloud deployment without explicit account IDs, billing controls, and approval"), the workspace *configuration* for prod is real, demonstrable Terraform work — but it won't actually be applied against a second live AWS account unless that's explicitly decided and approved, given the ongoing cost of running a mirrored environment (EKS control plane, NAT gateways, and interface VPC endpoints alone run roughly $200+/month if left running continuously).

**Q: Why is Azure "designed, not built" instead of a second fully-deployed cloud?**
A: Same reasoning as the single-AWS-account decision — doubling every cloud-specific integration (Entra vs. IAM Identity Center, ACR vs. ECR, AKS vs. EKS) costs weeks without deepening the target skills. Azure gets a full ADR mapping every AWS control to its named Azure equivalent, plus stub Terraform modules matching the interface — proving the design is portable without doubling the build.

---

## Git / GitHub / CI-CD mechanics

**Q: Why does `aws-dev-foundation` use "only trigger on specified path changes" instead of "always trigger on any push"?**
A: So a PR that only touches unrelated files (docs, a different module) doesn't trigger a plan/apply cycle for infrastructure it didn't change. It's scoped to `terraform/environments/dev/aws/**` and `terraform/modules/**` — the paths that actually affect what this workspace manages.

**Q: What's the practical difference between HCP Terraform's GitHub-App-based VCS connection and the older OAuth-based one?**
A: The GitHub App method uses per-user authorization against a shared, HashiCorp-owned app — more "personalized" for teams, but failures are hard to diagnose since delivery logs for a third-party-owned app aren't visible to the repo owner. The OAuth method authenticates as a single GitHub identity and creates a classic, visible webhook directly on the repo (`Settings → Webhooks → Recent Deliveries`), so a failed trigger shows an actual inspectable error instead of just silently not firing.

**Q: What's the difference between `git add -A`/`git add .` and `git add <specific-file>`, and why does this project always use the latter?**
A: `-A`/`.` stages everything changed in the working tree, including anything unexpected sitting around. Naming files explicitly stages only what you intend to commit — paired with checking `git status` before committing, this is the safety check against accidentally committing something unintended (stray edits, or worse, a secret).

**Q: Why commit a bootstrap `.tf` file immediately after applying it, rather than batching multiple bootstrap changes into one commit later?**
A: Git is supposed to be the source of truth for what's actually deployed. If a change is applied to real AWS infrastructure but the file sits uncommitted, the repo temporarily lies about what's running — and if that gap compounds across multiple changes, reconstructing an accurate commit history afterward gets harder each time.

---

## Cost awareness

**Q: What are the two AWS charges that make an idle demo environment more expensive than people expect, and why?**
A: The EKS control plane fee ($0.10/hr) and NAT Gateway hourly charge ($0.045/hr each) both bill continuously regardless of whether anything is actually happening — there's no "idle discount." A multi-AZ NAT setup plus an EKS control plane left running 24/7 adds up to real money even with zero traffic.

**Q: What's the practical mitigation for demoing a full environment (like a prod account) without paying for it continuously?**
A: Since it's all Terraform, "always-on" is a choice: `terraform apply` right before a demo/recording, `terraform destroy` immediately after. The control-plane and networking charges stop the moment the resources are gone, turning a $200+/month cost into a few dollars for the hours it actually existed.
