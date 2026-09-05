# Split YunoHost MCP into an unprivileged frontend and root broker

## Summary

Refactor the service so the public MCP process runs as `yunohost_mcp`, while a separate root-owned broker performs only explicitly authorized privileged YunoHost operations.

The public MCP API, NIP-98 authentication behavior, tool names, arguments, responses, policy rules, and audit semantics remain compatible. Package install/test workflows are now routed through named broker operations with bounded arguments; they are not yet isolated in a dedicated package sandbox and remain a separate hardening concern.

This aligns better with YunoHost’s packaging expectations around maintainability, security, upgradeability, and integration quality. See the official [packaging guidance](https://doc.yunohost.org/en/dev/packaging/) and [catalog publication guidance](https://doc.next.yunohost.org/en/packaging/publish/).

## Architecture and interfaces

- Keep `yunohost_mcp.service` as the public HTTP/MCP service, but run it as the existing `yunohost_mcp` system user.
- Add `yunohost_mcp-helper.service`, running as root with no network listener.
- Connect the two services through a root-owned Unix socket under `/run/yunohost_mcp/`.
- Keep Nginx forwarding HTTPS traffic only to the unprivileged frontend.
- Restrict the frontend with `NoNewPrivileges`, `ProtectSystem`, `ProtectHome`, `PrivateTmp`, limited filesystem access, and no unnecessary network capabilities.
- Give the helper only the filesystem and system interfaces required by YunoHost operations.

Define a private, versioned broker protocol:

```json
{
  "protocol": 1,
  "request_id": "...",
  "operation": "app.info",
  "arguments": {},
  "auth": {
    "method": "POST",
    "url": "...",
    "body": "..."
  }
}
```

The helper returns:

```json
{
  "protocol": 1,
  "request_id": "...",
  "ok": true,
  "result": {},
  "audit_id": null
}
```

Errors use stable codes such as `unauthenticated`, `forbidden`, `policy_violation`, `confirmation_required`, `unsupported`, `operation_failed`, and `internal_error`.

The helper must independently verify the signed request and reload `identity.toml`, `policy.toml`, and delegation state. The frontend’s authorization result must never be trusted as the sole privilege boundary.

## Privilege and operation routing

- Move read-only YunoHost operations behind typed helper methods where YunoHost imports require root.
- Revalidate write authorization and policy immediately before execution.
- Enforce confirmation IDs, owner co-signatures, backup-age checks, free-space checks, and audit records in the helper.
- Do not accept arbitrary shell commands, executable paths, environment variables, or unrestricted filesystem paths.
- Write audit records from the helper, including caller identity, operation, redacted arguments, outcome, and request ID.
- Expose service log retrieval through the frontend after helper-side validation of service names, time ranges, priorities, and grep patterns.
- Keep package install/test tools as explicit named broker operations with bounded arguments. They still execute YunoHost package scripts as root and should receive a dedicated sandbox before final catalog submission; no arbitrary command or executable operation is exposed.

## Package and migration changes

- Add the helper unit and socket lifecycle to install, upgrade, restore, remove, and change-url scripts.
- Preserve the existing data directory and all identities, policies, server keys, revoked delegations, and audit history.
- Add a migration that stops the existing root service, installs and validates the helper, starts the unprivileged frontend, verifies socket connectivity and a read-only MCP call, and records success.
- Retain a clearly documented rollback switch for the staged rollout.
- Ensure upgrade failure leaves either the previous root service or the new split service operational.
- Update `README.md`, `doc/ADMIN.md`, and install output to describe both services, the socket boundary, remaining package-test limitations, and recovery.
- Add maintainers, release metadata, and catalog-facing documentation before submission.

## Test and acceptance plan

Automate tests for:

- Frontend startup as `yunohost_mcp` and denial of writes to protected system paths.
- Root helper startup without a TCP listener.
- Unix socket rejection of all users except the frontend identity.
- Rejection of malformed, replayed, unsigned, and incorrectly scoped requests.
- Prevention of readonly-to-operator or readonly-to-administrator elevation through a compromised frontend.
- Compatibility of app, service, diagnosis, backup, domain, and log read calls.
- Continued enforcement of policy, confirmation, and owner co-signature for writes.
- Helper-owned audit entries with secret-shaped values redacted.
- Complete `service_logs` lines, clean empty results, and normalized application severity.
- Clean install, upgrade, backup, restore, change-url, and rollback on a YunoHost instance.
- Preservation of existing identities and the server Nostr identity.
- Package-test routing uses only named operations and bounded arguments; arbitrary commands and executable paths are rejected.

Acceptance requires a clean install/upgrade/restore cycle on the exact release tag, successful YunoHost integration tests, no unexplained MCP exceptions during the test matrix, and a security review of the root helper protocol.

## Assumptions and defaults

- Scope covers both the upstream Python service and this YunoHost package.
- The root Unix-socket broker is the privilege boundary.
- The public MCP API remains compatible.
- Rollout is staged with rollback support.
- Package-development workflows are brokered as named operations, but dedicated isolation remains future work.
- The helper is authoritative for authentication, authorization, policy, and auditing.
