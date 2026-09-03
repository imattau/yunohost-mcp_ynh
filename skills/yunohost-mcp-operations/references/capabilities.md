# YunoHost MCP capability reference

This is a reviewed snapshot of the upstream tool inventory and policy model. The connected server's live tool list and `whoami` response win if they differ.

## Scopes and roles

Scopes: `server.read`, `diagnosis.read`, `apps.read`, `apps.install`, `apps.upgrade`, `apps.remove`, `services.read`, `services.restart`, `logs.read`, `backups.read`, `backups.create`, `backups.restore`, `users.read`, `users.write`, `users.delete`, `domains.read`, `domains.write`, `system.update`, `system.upgrade`, `packages.inspect`, `packages.test`, `catalog.inspect`, `catalog.verify`, `catalog.publish`, `audit.read`, and `owner.approve`.

Role bundles:

| Role | Capability |
|---|---|
| `readonly` | All read scopes: server/diagnosis/apps/services/logs/backups/users/domains, system update metadata, package inspection, catalog inspection and verification |
| `operator` | `readonly` plus `services.restart`, `backups.create` |
| `app-admin` | `operator` plus `apps.install`, `apps.upgrade`, `apps.remove`, `backups.restore`, `domains.write`, `users.write`, `users.delete` |
| `package-developer` | `readonly` plus `packages.test`, `apps.install`, `apps.upgrade`, `apps.remove`, `backups.create`, `catalog.publish`, `domains.write` |
| `administrator` | Every scope, including `audit.read` and `owner.approve` |

Role bundles are not strictly hierarchical: `package-developer` is not `app-admin`, and roles combine by union. An identity with no roles has no operational scopes. A valid NIP-98 signature authenticates identity; it does not grant authorization.

## Tool inventory by capability

### Identity and governance

- `whoami` — resolved caller identity, roles, and scopes.
- `server_identity` — server npub/hex identity needed when constructing delegations.
- `audit_list`, `audit_get` — administrator-only audit trail reads.
- `approve_operation` — administrator owner co-signature for a pending high-risk confirmation; approval does not execute.

### Server, diagnosis, and operations

- `server_info`, `validate_server`, `health_check`
- `diagnosis_run`, `diagnosis_get`, `diagnose_app`
- `operations_list`, `operation_status`, `operation_logs`
- `services_list`, `service_status`, `service_logs`, `service_restart`

### Apps and updates

- `apps_list`, `app_info`, `app_resources`
- `app_install`, `app_upgrade`, `app_remove`
- `plan_app_upgrade`, `execute_plan`, `safe_upgrade`, `repair_app`
- `updates_check`, `updates_refresh`

### Backups

- `backups_list`, `backup_create`, `backup_restore`

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

## Policy gates

The built-in policy requires:

| Operation | Gate |
|---|---|
| `catalog_publish` | confirmation |
| `domain_add` | confirmation |
| `app_upgrade` / `execute_plan` / `safe_upgrade` | recent backup and at least 2 GB free; hard blockers, not confirmable overrides |
| `app_remove` | confirmation and backup within 24 hours by default |
| `backup_restore` | confirmation plus different administrator identity co-signature |
| `system_upgrade` | confirmation plus different administrator identity co-signature |
| `user_create` / `user_update` | confirmation |
| `user_delete` | confirmation plus different administrator identity co-signature |
| `user_group_create` / `user_group_update` | confirmation |
| `user_group_delete` | confirmation plus different administrator identity co-signature |
| `user_permission_add` / `user_permission_remove` | confirmation plus different administrator identity co-signature |

The local `policy.toml` may change confirmation settings, but the live server's response is authoritative. Every write is serialized and audited; responses are redacted for secret-shaped values.
