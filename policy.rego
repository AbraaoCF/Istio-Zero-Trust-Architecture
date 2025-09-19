# save this as policy.rego
package envoy.authz

default allow = false

allow if {
    # Allow by default if not a private path
    not is_private_path
}

allow if {
    # Allow if private path and user is admin
    is_private_path
    input.attributes.request.http.headers["x-user"] == "admin"
}

is_private_path if {
    input.attributes.request.http.headers[":path"] == "/productpage"
}