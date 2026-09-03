## Connecting an MCP client

Every request to `https://your-domain/mcp` authenticates with a [NIP-98](https://github.com/nostr-protocol/nips/blob/master/98.md) signed event using its own Nostr key — there's no username/password and no YunoHost SSO involved. The pubkey it signs with must be in `identity.toml` (see below) with a role that grants what it's trying to do, or every call is rejected.

Mainstream clients (Claude Desktop, Codex CLI, etc.) can't sign that header themselves, so point them at `yunohost-mcp-connect` (installed alongside the server, in this app's own venv) instead of the URL directly — see the upstream [README](https://github.com/imattau/yunohost-mcp/blob/master/README.md#connecting-claude-desktop-or-codex) for exact `claude_desktop_config.json`/`config.toml` snippets.

## Granting access: identity.toml

`$data_dir/identity.toml` (typically `/home/yunohost.app/yunohost_mcp/identity.toml`) is the access-control file. Your own npub was seeded into it at install time as `administrator`. Two ways to grant another identity access:

- **Webadmin (no SSH needed):** Apps → YunoHost MCP → Config panel → *Agent access* → *Grant a new identity*. Enter the agent's npub, a display name, pick a role, and optionally an expiry date, then click *Grant access*. The same tab's *Current identities* section shows everyone currently granted, and *Revoke an identity* removes one by npub (it refuses to remove the last remaining administrator, to stop you locking yourself out by accident).
- **SSH, editing the file directly:**

  ```toml
  [identity."npub1..."]
  name = "Codex development agent"
  roles = ["package-developer"]
  expires = "2026-12-31T00:00:00+00:00"   # optional
  ```

Available roles: `readonly`, `operator`, `app-admin`, `package-developer`, `administrator`. See the upstream repo's `PLAN.md` and `src/yunohost_mcp/policy/roles.py` for exactly which scopes each grants. Either way, no restart is needed — the file is re-read on every request.

An entry with no `expires` never expires. Removing an entry (or letting it expire) immediately revokes that identity, including anything it was ever delegated the authority to further delegate. To revoke one specific delegation without touching the delegator's own entry, add its event id to the config panel's *Revoked delegations* list (or `$data_dir/revoked_delegations.toml`'s `revoked` array directly) — see [delegation](https://github.com/imattau/yunohost-mcp/blob/master/PLAN.md) and the upstream `yunohost-mcp-delegate` tool, which prints the event id after signing one.

## Adjusting safety policy: policy.toml

`$data_dir/policy.toml` overrides the built-in defaults (a recent backup + minimum free space required before an app upgrade proceeds; app removal, backup restore, and system upgrade all require confirmation; the latter two additionally require a second identity's approval). See the upstream repo's `src/yunohost_mcp/policy/rules.py` for the exact schema — this file is optional; a missing one means the defaults apply unmodified.

## Owner co-signing

`system_upgrade` and `backup_restore` require two independently signed calls from two *different* identities before they execute: one requests the operation, a different one (holding the `administrator` role) calls `approve_operation` on the resulting `confirmation_id`, then the original requester executes it. No single agent identity can perform either operation alone, by design.

## The audit trail

Every write is logged to `$data_dir/audit.jsonl` (one JSON object per line: caller pubkey, tool, redacted arguments, outcome). Query it directly, or via the `audit_list`/`audit_get` MCP tools (administrator-only).

## This server's own Nostr identity

Generated on first run at `$data_dir/server_identity.key` (0600, root-owned) — call the `server_identity` tool to see its npub. This is what a [delegation](https://github.com/imattau/yunohost-mcp/blob/master/PLAN.md) (an owner granting a disposable agent identity a subset of their own access, without sharing their private key) must name in its `server` tag to be accepted here.

## A privilege note

This service runs **as root**, not as an unprivileged `yunohost_mcp` system user. That's not an oversight: it imports YunoHost's own Python modules directly in-process, and the underlying operations (`systemctl`, `apt`, LDAP admin, writes under `/etc/yunohost/`) genuinely require root to function at all against a real YunoHost install. Splitting this into an unprivileged HTTP-facing process plus a narrow privileged helper is documented upstream as real, not-yet-built future work — not something this package already does. Every request is still authenticated, scope-checked, and audited before it reaches any YunoHost call; there is no way to reach this service's privileges without a validly-signed request from an identity `identity.toml` already grants that specific action to.

## Logs

```
journalctl -u yunohost_mcp -f
```

(or the app's Logs tab in the YunoHost admin panel).

## If you get locked out

Edit `$data_dir/identity.toml` directly over SSH as root and add your npub back with the `administrator` role - no service restart needed.
