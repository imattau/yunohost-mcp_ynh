# YunoHost MCP capability reference

This is a reviewed snapshot of the upstream tool inventory and policy model. The connected server's live tool list and `whoami` response win if they differ.

## Scopes and roles

Scopes: `server.read`, `diagnosis.read`, `apps.read`, `apps.install`, `apps.upgrade`, `apps.remove`, `apps.config.read`, `apps.config.write`, `services.read`, `services.restart`, `logs.read`, `backups.read`, `backups.create`, `backups.restore`, `users.read`, `users.write`, `users.delete`, `domains.read`, `domains.write`, `system.update`, `system.upgrade`, `system.migrate`, `firewall.read`, `firewall.write`, `packages.inspect`, `packages.test`, `catalog.inspect`, `catalog.verify`, `catalog.publish`, `audit.read`, and `owner.approve`.

Role bundles (strictly hierarchical below `administrator` - each a superset of the one before, plus its own scopes):

| Role | Capability |
|---|---|
| `readonly` | All read scopes: server/diagnosis/apps/services/logs/backups/users/domains/app-config, system update metadata, package inspection, catalog inspection and verification |
| `operator` | `readonly` plus `services.restart`, `backups.create` |
| `app-admin` | `operator` plus `apps.install`, `apps.upgrade`, `apps.remove`, `apps.config.write`, `backups.restore`, `domains.write`, `users.write`, `users.delete` |
| `package-developer` | `app-admin` plus `packages.test`, `catalog.publish` |
| `administrator` | Every scope, including `audit.read` and `owner.approve` |

An identity with no roles has no operational scopes. A valid NIP-98 signature authenticates identity; it does not grant authorization.

## Tool inventory by capability

### Identity and governance

- `whoami` — resolved caller identity, roles, and scopes.
- `server_identity` — server npub/hex identity needed when constructing delegations.
- `audit_list`, `audit_get` — administrator-only audit trail reads.
- `approve_operation` — this server's one configured owner approves a pending high-risk confirmation; holding the `administrator` role is necessary but not sufficient (the caller must be the exact owner pubkey). Approval does not execute the operation.
- `approval_get`, `approval_status` — authoritative pending-confirmation record (tool, arguments, `operation_hash`, expiry, approval state), visible to the confirmation's own requester or the owner only. What `yunohost-mcp-approve` calls before asking the owner to sign anything - prefer these over trusting a locally-supplied plan.

### Server, diagnosis, and operations

- `server_info`, `validate_server`, `health_check`
- `diagnosis_run`, `diagnosis_get`, `diagnose_app`
- `operations_list`, `operation_status`, `operation_logs`
- `services_list`, `service_status`, `service_logs`, `service_restart`

### Apps and updates

- `apps_list`, `app_info`, `app_resources`
- `app_install`, `app_upgrade`, `app_remove`, `app_change_url`
- `app_config_get` — read an installed app's config-panel settings; call with `full=True` first to see the exact dotted key path before writing.
- `app_config_set` — write one config-panel setting (`apps.config.write`, confirmation-gated). `key` must be the exact dotted `<panel>.<section>.<option>` id from `app_config_get(..., full=True)`, not a label or bare option name - a panel can reuse the same option name across sections.
- `plan_app_upgrade`, `execute_plan`, `safe_upgrade`, `repair_app`
- `updates_check`, `updates_refresh`

### Backups

- `backups_list`, `backup_create`, `backup_restore`

### System migrations

- `migrations_list`, `migrations_state`, `migrations_run`

### Firewall

- `firewall_list`, `firewall_is_open`, `firewall_open`, `firewall_close`, `firewall_reload`

### Domains

- `domains_list`, `domain_add`

### Users, groups, and app permissions

- `users_list`, `user_create`, `user_update`, `user_delete`
- `user_group_list`, `user_group_create`, `user_group_update`, `user_group_delete`
- `user_permission_list`, `user_permission_add`, `user_permission_remove`

### Package development

- `package_inspect`, `package_lint`, `package_logs`
- `package_install_test`, `package_upgrade_test`, `package_backup_test`, `package_restore_test`
- `package_change_url_test`, `package_remove_test`, `package_run_tests`, `test_package`

### Catalog

- `catalog_package_inspect`, `catalog_publish_plan`, `catalog_verify`, `catalog_publish`
- `catalog_list` — the whole catalogue (every declared app across every publisher, trust-filtered), queried fresh from the configured relays on every call - not just this server's own `apps_list`. Use this to answer "what's available in the catalogue" rather than assuming installed apps are the full picture.

## Policy gates

The built-in policy requires:

| Operation | Gate |
|---|---|
| `catalog_publish` | confirmation |
| `domain_add` | confirmation |
| `app_config_set` | confirmation |
| `app_upgrade` / `execute_plan` / `safe_upgrade` | recent backup and at least 2 GB free; hard blockers, not confirmable overrides |
| `app_remove` | confirmation and backup within 24 hours by default |
| `backup_restore` | confirmation plus the server's owner approving via `approve_operation` |
| `system_upgrade` | confirmation plus owner approval |
| `migrations_run` | confirmation plus owner approval |
| `user_create` / `user_update` | confirmation |
| `user_delete` | confirmation plus owner approval |
| `user_group_create` / `user_group_update` | confirmation |
| `user_group_delete` | confirmation plus owner approval |
| `user_permission_add` / `user_permission_remove` | confirmation plus owner approval |
| `firewall_open` / `firewall_close` / `firewall_reload` | confirmation plus owner approval |

"Owner approval" above means: the server's one configured owner (fixed at install time, independent of who else holds the `administrator` role) separately signs an `approve_operation` call, typically through `yunohost-mcp-approve`'s NIP-46 flow - the requester's own signature never satisfies this by itself. See `approval_get`/`approval_status` above for how to check status without guessing.

The local `policy.toml` may change confirmation settings, but the live server's response is authoritative. Every write is serialized and audited; responses are redacted for secret-shaped values.
