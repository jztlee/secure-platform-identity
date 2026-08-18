# Threat model

Covers token theft, privilege escalation, confused deputy, SCIM abuse,
supply chain compromise (mutable Action tags, unpinned providers),
Terraform state/secret exposure, K8s escape, and agent delegation (spec
§14). Started in Phase 3 and extended as each new component introduces new
attack surface — not written once at the end.
