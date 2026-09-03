package platform.authz

default allow = false

allow if {
	input.action == "read"
	role_matches(input.subject, "read-only")
}

allow if {
	input.action == "read"
	role_matches(input.subject, "developer")
}

allow if {
	input.action in ["read", "write"]
	role_matches(input.subject, "admin")
}

role_matches(subject, role) if {
	subject_roles[subject][_] == role
}

subject_roles := {
	"user:lee": ["admin"],
	"user:dev-test": ["developer"],
}