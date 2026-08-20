# Glossary

Running reference of terms and tools introduced as the project progresses.
Organized by category (not phase), since categories get reused — e.g.
"AWS" picks up new terms in nearly every phase. New sections get added
as new categories of tooling show up (Kubernetes, Go, CI/CD, etc.).

*Last updated: through Phase 2.*

## Git / GitHub workflow

- **Branch protection rule / repository ruleset** — GitHub settings that
  block direct pushes to a branch, requiring changes to go through a
  reviewed pull request instead.
- **Pull request (PR)** — a proposed merge from one branch into another,
  shown as a diff for review before it lands.
- **Staging area** — what `git add` puts files into before a commit;
  distinct from the working directory (unstaged edits) and the commit
  history itself.
- **Remote** (`origin`) — the GitHub-hosted copy of the repo, as opposed
  to the local copy on a laptop.
- **Upstream** (`-u` flag on `git push`) — links a local branch to its
  remote counterpart so future `push`/`pull` don't need the remote/branch
  named explicitly.
- **Local vs. remote branch** — two independent copies of a branch that
  only sync when you explicitly `push` or `pull`; merging on GitHub does
  not update a local branch automatically.

## Terraform core concepts

- **HCL** — HashiCorp Configuration Language, the syntax `.tf` files are
  written in.
- **Provider** — a plugin that lets Terraform talk to a specific system
  (e.g. `hashicorp/aws`, `hashicorp/tls`).
- **Resource** — something Terraform *creates and manages*
  (`resource "aws_iam_openid_connect_provider" ...`).
- **Data source** — something Terraform *reads* but doesn't manage
  (`data "tls_certificate" ...`).
- **Output** — a value exposed after apply, for humans or other Terraform
  configs to read.
- **State** — Terraform's record of what it's created and how that maps
  to real infrastructure. Treated as sensitive (spec §10) since it stores
  full resource attributes in plaintext.
- **State locking** — prevents two runs from modifying the same state
  simultaneously; a stale lock from an interrupted run can block later
  runs until manually cleared.
- **`.terraform.lock.hcl`** — the dependency lock file that pins exact
  resolved provider versions; committed to git so every run uses
  identical, verified provider builds.
- **Version constraint** (`~>`, the "pessimistic operator") — allows
  patch/minor version updates but blocks major-version jumps.

## HCP Terraform specific

- **Organization** — the top-level account grouping in HCP Terraform.
- **Project** — a folder-like grouping of workspaces, used as an access
  control boundary.
- **Workspace** — one deployable unit of Terraform config, with its own
  state and variables.
- **Execution mode** (Local vs. Remote) — where `terraform apply` actually
  runs: on HCP Terraform's own servers (Remote) or on the user's machine,
  with state still stored centrally (Local).
- **CLI-driven vs. VCS-driven workflow** — whether runs are triggered
  manually from a terminal or automatically by a git push/PR.
- **State sharing** — controls whether other workspaces can read a given
  workspace's outputs via remote state; defaults to nothing shared.

## Identity & security

- **OIDC** (OpenID Connect) — a protocol for proving identity via signed,
  short-lived tokens instead of long-lived static secrets.
- **Federation** — trusting an external identity provider's tokens instead
  of managing credentials directly.
- **IAM** (Identity and Access Management) — AWS's permission system.
- **Trust policy** — the rule on an IAM role deciding *who* is allowed to
  assume it (checked against a token's claims for OIDC-based roles).
- **Assume role** — exchanging a token or credential for a temporary set
  of permissions.
- **Audience** (`aud` claim) — who a token is intended for; AWS checks
  this against the OIDC provider's configured `client_id_list`.
- **Subject** (`sub` claim) — who/what a token represents — for HCP
  Terraform, a string encoding the org/project/workspace/run-phase.
- **Thumbprint** — a cryptographic fingerprint of a TLS certificate, used
  to validate an OIDC issuer's identity.
- **Least privilege** — granting only the exact permissions needed for a
  task, nothing more.
- **Static vs. dynamic (temporary) credentials** — a long-lived secret
  that persists until manually rotated, vs. one that expires quickly and
  is minted on demand.
- **Confused deputy** — a security failure where a trusted system is
  tricked into using its own legitimate authority on behalf of an
  unauthorized party, because the check meant to distinguish "authorized
  caller" from "anyone" was too weak or missing.
- **ARN** (Amazon Resource Name) — AWS's unique identifier format for
  every resource.

## Tooling / environment

- **arm64 vs. x86_64** — CPU architectures (Apple Silicon vs. Intel);
  mismatches between a tool's build and the host architecture can cause
  silent performance problems.
- **Rosetta 2** — Apple's on-the-fly translator for running Intel
  binaries on Apple Silicon hardware; translation overhead can be
  significant for very large binaries on first execution.
