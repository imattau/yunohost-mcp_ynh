# Owner Approval and NIP-46 Implementation Plan

## Purpose

Make high-risk YunoHost MCP operations practical for single-person self-hosted servers — the primary target use case — via an interactive owner approval step.

The owner’s existing Nostr identity should remain the default owner identity. A separate approval key is optional hardening, not a prerequisite.

**v1 scope: `solo` only.** A single-operator YunoHost server is the primary use case, so v1 implements only the `solo` profile: one owner npub, no separate owner list, no membership model. `household`, `team`, and `strict` (multi-owner, distinct-approver, threshold) are out of scope for v1 and mentioned below only to keep the design from painting itself into a corner — they are not being built now. This removes the owner-membership-store, delegation-for-approval-rights, and multi-party audit work from the initial delivery; owner is simply `admin_npub`.

## Current state

- This repository is the YunoHost packaging layer.
- It currently pins upstream `yunohost-mcp` v0.4.0.
- The upstream server authenticates MCP requests with NIP-98.
- High-risk operations use `approve_operation` with the configured single owner identity and NIP-46 step-up flow.
- The install-time `admin_npub` is already the user’s normal administrator identity and is preserved as the configured owner.
- The upstream package exposes the `yunohost-mcp-approve` helper; packaging still needs to document and validate its installation-time NIP-46 setup.

The core enforcement changes belong in the upstream MCP repository; this repository should package and configure the resulting release.

## Desired policy model

v1 implements a single approval profile:

- `solo`: the request is signed by the agent's own (delegated) key, and the configured owner (`admin_npub`) approves it through their own NIP-46 signer — the owner's private key never signs the original request, only the step-up approval.

`household` (several owner npubs, any may approve), `team` (requester and approver must be different approved npubs), and `strict` (configurable threshold, e.g. 2-of-3) are deferred past v1 — see "v1 scope" above. Where practical, name config fields and code paths so a later profile field can be added without a breaking migration, but do not build the membership/threshold logic now.

Approval should remain required for operations currently considered high risk, including restore, system upgrade, destructive identity changes, permission changes, and firewall changes, subject to the configured policy.

## Trust and key boundaries

The YunoHost MCP server must never hold or access the owner’s private key or NIP-46 signer.

The server is responsible for:

- creating and storing pending approval records;
- calculating and checking the canonical operation hash;
- checking policy, owner membership, expiry, nonce, and replay state;
- recording audit events;
- executing only after valid approval.

An external approval helper is responsible for:

- retrieving the pending operation;
- showing the owner the exact target, action, arguments, impact, requester, and expiry;
- connecting to the owner’s NIP-46 signer;
- submitting the signed `approve_operation` request.

In `solo` mode, the requester is the agent's own delegated key (see the existing NIP-46/Nostr delegation capability), and the owner's normal npub is used only for the step-up approval — never for the original request. This keeps the owner's signer out of the automated request path entirely, so approval is a real human-in-the-loop event rather than a second API call under the same identity. A dedicated cosigner npub, distinct from the owner's everyday identity, may be added later for household/team/strict profiles.

## Approval protocol

When a protected tool is first called, create a pending record containing:

```text
confirmation_id
operation_id
operation_hash
tool
canonical_arguments
target
requester_npub
created_at
expires_at
required_approval_mode
```

Calculate `operation_hash` as a SHA-256 digest of canonical JSON containing the tool, canonical arguments, target, server identity, requester npub, and confirmation ID.

The approval helper must obtain the authoritative record from the server before asking the owner to sign. The owner’s approval must be bound to the same operation hash. Any argument or target change invalidates the approval.

The server must reject approvals when:

- the approver is not the configured owner (`admin_npub`);
- the confirmation is missing, expired, consumed, or revoked;
- the operation hash does not match;
- the policy prerequisite is no longer satisfied;
- the approval nonce or signed request has been replayed.

The approval is a separate authenticated MCP request signed through NIP-46. Do not rely on a bare confirmation ID or an unsigned client-side claim.

**Storage:** the upstream implementation uses a shared SQLite confirmation store when packaged split-service mode is enabled. This allows the unprivileged frontend and root helper to complete one confirmation flow across processes; the file is group-only (`0660`) and lives under the persistent data directory. In-memory storage remains available for local single-process development. SQLite does not by itself provide multi-host coordination, and owner-approval expiry remains configurable (defaulting to a longer window than ordinary confirmations).

## NIP-46 helper

Create a companion command, tentatively:

```text
yunohost-mcp-approve \\
  --server https://host.example/mcp \\
  --confirmation-id <id>
```

The helper should:

1. connect to the server using the owner identity;
2. retrieve the pending approval details;
3. display a concise but complete impact summary;
4. require an explicit local confirmation;
5. use NIP-46 `sign_event` through the owner’s signer;
6. submit `approve_operation` with the operation hash;
7. report approval status and next action to the requester.

Use a QR-based `nostrconnect://` bootstrap flow where supported. Store only the NIP-46 connection/session information required by the helper; never store an nsec or private key.

Request the narrowest signer permissions possible. Ideally the helper should only obtain permission to sign the NIP-98 request needed for owner approval.

NIP-46 reference: https://nips.nostr.com/46

## Optional encrypted-DM delivery

Encrypted Nostr messages may notify the owner that approval is pending, but they must not be authoritative.

Recommended flow:

1. server or helper sends a short NIP-44 notification containing the confirmation ID and expiry;
2. owner opens the approval helper;
3. helper fetches authoritative details from the server;
4. owner reviews and approves through NIP-46.

Do not use deprecated NIP-04. NIP-17/NIP-59 wrapping can be considered later if metadata privacy is important.

NIP-44 reference: https://nips.nostr.com/44

## Upstream MCP changes

Implement in `imattau/yunohost-mcp`:

- single-owner identity configuration (`admin_npub`) and migration behavior;
- `solo` approval mode, replacing the current different-identity requirement for high-risk tools;
- operation hash and canonical argument handling;
- `approval_get` and `approval_status` read tools;
- expanded `approve_operation` validation for step-up (agent-delegated requester, owner approver);
- owner identity details in audit records;
- expiry, replay protection, and consumed-approval handling;
- tests for solo step-up, mismatch, expiry, and replay cases;
- the approval helper and NIP-46 integration;
- documentation and example policy configuration.

Backward compatibility:

- if no explicit owner exists, use the original bootstrap administrator npub as owner;
- do not silently make every administrator an owner;
- reject ambiguous or malformed owner configuration safely.

Not in v1 (deferred, see "v1 scope"): owner list/membership, `household`/`team`/`strict` profiles, threshold approval, multi-owner configuration actions.

## Packaging changes

After an upstream release containing the feature:

- update `manifest.toml` to the new upstream version and checksum;
- ensure `admin_npub` seeds both administrator access and owner configuration;
- preserve owner configuration across upgrade, backup, restore, and reinstall flows;
- update `doc/ADMIN.md`, `doc/PRE_INSTALL.md`, and README guidance;
- update the packaged skill and capability reference;
- document the approval helper installation and NIP-46 setup;
- add package-level upgrade/configuration tests.

Do not vendor a partial upstream implementation into this packaging repository.

## Verification and acceptance criteria

### Solo owner

- A user installs the package with their usual npub, recorded as owner.
- The agent operates under its own delegated key, scoped from the owner's identity.
- A high-risk request from the agent pauses with a clear approval record.
- The owner approves through the external NIP-46 signer, using their own npub — never the agent's delegated key.
- The original request can then execute.
- The agent cannot approve silently without the owner’s interactive signer step, because it never holds the owner's key.

### Multi-owner (deferred past v1)

Not implemented in v1; kept here as the shape a later `household`/`team`/`strict` phase should satisfy:

- An owner can add or remove approved owner npubs through an explicit, audited configuration action.
- `team` rejects same-npub approval where separation is required.
- `strict` enforces the configured threshold.
- Removing an owner cannot lock out the last administrator without an explicit recovery path.

### Safety

- Changed arguments, targets, or operation hashes invalidate approvals.
- Expired, replayed, consumed, and revoked approvals are rejected.
- Timeouts are treated as unknown outcomes and do not cause duplicate operations.
- Logs and audit records redact secrets and avoid storing private signer material.
- Policy failures for backup age or free space remain hard blockers.

### Packaging

- Existing installations retain identities, owner state, policies, server keys, delegations, and audit history.
- Fresh install, upgrade, backup/restore, and configuration-panel paths are tested.
- The package points to a released upstream version that contains the actual server and helper implementation.

## Suggested delivery sequence

1. Implement and test owner/approval model upstream.
2. Implement operation hashing and approval status tools upstream.
3. Implement the NIP-46 approval helper.
4. Add optional DM notifications.
5. Release upstream.
6. Bump and test this YunoHost package.
7. Update the operational skill and administrator documentation.
