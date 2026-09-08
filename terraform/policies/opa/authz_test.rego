package platform.authz

test_admin_can_write if {
	allow with input as {"subject_id": "user:lee", "action": "write"}
}

test_developer_can_read if {
	allow with input as {"subject_id": "user:dev-test", "action": "read"}
}

test_developer_cannot_write if {
	not allow with input as {"subject_id": "user:dev-test", "action": "write"}
}

test_unknown_subject_denied if {
	not allow with input as {"subject_id": "user:stranger", "action": "read"}
}