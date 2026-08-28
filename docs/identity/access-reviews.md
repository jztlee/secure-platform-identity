# Access review log

One entry per review — quarterly, or off-cycle after any
group/permission-set change or offboarding (see docs/identity/README.md).

## 2026-08-28 — initial baseline

**Reviewer:** project operator

**Scope checked:** Okta group membership, IAM Identity Center account
assignments, console sign-in history.

**Findings:** One human provisioned (`platform-admin`), matching one
Okta group and one IAM Identity Center assignment — no drift possible
yet, nothing to compare against. `developer`, `security-auditor`, and
`read-only` groups exist with working permission sets but zero
assigned users, so no sign-in history exists for them either.

**Actions taken:** None required. This entry exists to establish the
log format and cadence before there's anything substantive to review.

**Next review due:** 2026-11-28 (quarterly).
