## Connecting an MCP client

Every request to `https://your-domain/mcp` authenticates with a [NIP-98](https://github.com/nostr-protocol/nips/blob/master/98.md) signed event using its own Nostr key — there's no username/password and no YunoHost SSO involved. The pubkey it signs with must be in `identity.toml` (see below) with a role that grants what it's trying to do, or every call is rejected.

Mainstream clients (Claude Desktop, Codex CLI, etc.) can't sign that header themselves, so point them at `yunohost-mcp-connect` (installed alongside the server, in this app's own venv) instead of the URL directly — see the upstream [README](https://github.com/imattau/yunohost-mcp/blob/master/README.md#connecting-claude-desktop-or-codex) for exact `claude_desktop_config.json`/`config.toml` snippets.

**Give every client its own key file.** `yunohost-mcp-connect`'s `YUNOHOST_MCP_CLIENT_KEY_FILE` *is* the identity: whichever key signs a request determines its role and scopes, nothing else. Point two different tools (or two different config files for the same tool — e.g. a project-local `.codex/config.toml` shadowing `~/.codex/config.toml`) at the same key file, and the second one silently inherits the first's exact permissions — no error, no warning, it just authenticates as if it were the other identity. This is easy to hit by accident (copy-pasting one client's MCP config as a starting point for another's and forgetting to swap the key path), and unlike a wrong password or a malformed key it produces no failure to notice - it just works, as the wrong identity.

When wiring up a new AI tool against this server, generate it a key of its own rather than reusing a key file that already works for something else:

```
yunohost-mcp-connect --generate-key ~/.config/yunohost-mcp/<tool-name>.key
```

This writes the key (0600; refuses to overwrite an existing file) and prints its npub. Point that tool's `YUNOHOST_MCP_CLIENT_KEY_FILE` at the new file, and grant *that* npub whatever role is actually appropriate for it (see below) - not the role you already gave a different tool.

## Granting access: identity.toml

`$data_dir/identity.toml` (typically `/home/yunohost.app/yunohost_mcp/identity.toml`) is the access-control file. Your own npub was seeded into it at install time as `administrator`. Note that the `administrator` role and being the **owner** (see "Owner approval" below) are separate things: granting another identity `administrator` here gives it every scope *except* the authority to approve owner-gated operations — that stays with the install-time npub regardless. Two ways to grant another identity access:

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

## Owner approval

`system_upgrade`, `backup_restore`, `system_migrate`, `user_delete`/`user_group_delete`, permission changes, and firewall changes all need a second, independently signed approval on top of the requester's own confirmation before they execute — an agent's own signature is never enough by itself for these.

The **owner** who approves is fixed at install time to the npub you gave the install form (`admin_npub`) — see `YUNOHOST_MCP_OWNER_NPUB` in `conf/systemd.service`. This is deliberate and explicit: granting a second (or third) `administrator` identity later, from the config panel or `identity.toml` directly, does **not** change who the owner is or split approval authority — it stays pinned to the original install-time npub regardless of how many administrators exist.

**If a signer is paired** (see above), you usually don't need to do anything at all: the moment such an operation is requested, the server itself opens a live connection to your paired signer and asks it to sign a small, human-readable approval covering exactly that request — a real push prompt on your signer app, no command to run or button to click. Approving there is enough; the sections below (manual `approve_operation` via the webadmin or CLI) are the fallback for when no signer is paired yet, the push is declined or times out, or you're checking on something asynchronously. Disable the automatic push entirely with `YUNOHOST_MCP_OWNER_PUSH_APPROVAL_ENABLED=false` in `conf/systemd.service` if you'd rather always approve manually.

**Webadmin (no SSH needed):** Apps → YunoHost MCP → Config panel → *Owner approval*. This is offered as an optional, recommended step at install time too (have your signer app open and ready before continuing installation — it waits briefly for pairing, but never fails the install if you skip it or it times out):

- *Signer status* shows whether a NIP-46 signer is paired yet - and, if not, the `nostrconnect://` link and QR code to scan, generated as soon as the panel loads (no button click needed) and stable across reloads until it's used or expires. It automatically looks up your own published relay list (NIP-65) from your npub and prefers those relays, falling back to a small set of sane defaults if you haven't published one.
- *Pair or re-pair your signer* completes pairing against the code already shown above, once you've scanned it. Safe to re-run any time, e.g. after switching signer apps or if it times out (the same code stays valid - just try again). Listing *Additional relays* here and clicking generates a fresh code that includes them. If your signer app can export a `bunker://` connection string itself (a separate feature from scanning a code - check for an "add a connection" option), paste it into *Or paste a bunker:// URI* instead and pairing completes immediately, no code involved.
- *Approve a pending operation* takes the `confirmation_id` an agent gives you and asks your paired signer to review and sign it — clicking the button is your explicit approval, same as typing `yes` on the CLI below.

**SSH, using the CLI directly:** the owner runs the upstream [`yunohost-mcp-approve`](https://github.com/imattau/yunohost-mcp#approving-high-risk-operations-yunohost-mcp-approve) tool from their own machine, on whatever device holds their [NIP-46](https://nips.nostr.com/46) remote signer app (Amber, nsec.app, ...) — the owner's private key never touches this server, nor the requesting agent's machine:

```
yunohost-mcp-approve pair                 # one-time
yunohost-mcp-approve status               # check pairing state without a live round trip
yunohost-mcp-approve approve --server https://your-domain/mcp --confirmation-id confirm-...
```

It fetches the authoritative pending-operation record from the server (`approval_get`/`approval_status` MCP tools — never a locally-supplied claim), displays the exact tool, arguments, and `operation_hash`, and requires typing `yes` before submitting a NIP-98-signed `approve_operation` call. Once approved, the original requester can retry its call; approving does not itself execute anything.

Either path uses the same paired session — pairing once (via either the webadmin or the CLI) is enough for both.

This is v1's `solo` profile: one owner, no multi-party threshold. Household/team/multi-owner approval is documented as a future direction upstream, not something this package currently supports.

## The audit trail

Every write is logged to `$data_dir/audit.jsonl` (one JSON object per line: caller pubkey, tool, redacted arguments, outcome). Query it directly, or via the `audit_list`/`audit_get` MCP tools (administrator-only).

## This server's own Nostr identity

Generated on first run at `$data_dir/server_identity.key` (0600, root-owned) — call the `server_identity` tool to see its npub. This is what a [delegation](https://github.com/imattau/yunohost-mcp/blob/master/PLAN.md) (an owner granting a disposable agent identity a subset of their own access, without sharing their private key) must name in its `server` tag to be accepted here.

## A privilege note

The HTTP-facing service runs as the unprivileged app user. Root-only YunoHost operations cross a local Unix socket into a separate root helper, which accepts only explicitly registered operations and independently re-authenticates the original NIP-98 request. Every request is still authenticated, scope-checked, policy-checked and audited; the helper is not a shell or generic execution interface. Unsupported adapter operations fail closed until a typed broker operation is added.

## Logs

```
journalctl -u yunohost_mcp -f
```

(or the app's Logs tab in the YunoHost admin panel).

## If you get locked out

Edit `$data_dir/identity.toml` directly over SSH as root and add your npub back with the `administrator` role - no service restart needed.
