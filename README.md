# YunoHost MCP, packaged for YunoHost

[![Version](https://img.shields.io/badge/Version-0.1.0~ynh1-blue)](https://github.com/imattau/yunohost-mcp-ynh)
[![License: AGPL--3.0--or--later](https://img.shields.io/badge/License-AGPL--3.0--or--later-lightgrey)](https://github.com/imattau/yunohost-mcp/blob/master/LICENSE)
[![Packaging format: 2](https://img.shields.io/badge/Packaging_format-2-green)](https://yunohost.org/packaging_apps)

A [Model Context Protocol](https://modelcontextprotocol.io) server that lets AI coding agents (Claude, Codex, and other MCP clients) inspect, diagnose, and administer this YunoHost server — and develop/test `_ynh` app packages — through typed, policy-controlled tools, instead of arbitrary shell access.

Every request authenticates with a [NIP-98](https://github.com/nostr-protocol/nips/blob/master/98.md) signed Nostr event, not a YunoHost user account. What that identity is allowed to do is a separate, explicit decision made from an `identity.toml` file you control — a valid signature only proves *who*, never *what*. Reads are broad by default; writes are scope-gated, policy-checked (backup and free-space requirements before an upgrade, for instance), and audited, and the riskiest operations (system upgrade, backup restore, firewall changes, and a few others) require the server's configured **owner** to separately approve them through their own [NIP-46](https://nips.nostr.com/46) remote signer, using the `yunohost-mcp-approve` tool — an agent's own signature is never enough by itself.

🛠️ Upstream project: <https://github.com/imattau/yunohost-mcp>

💬 Discuss this package: [Armada community](https://armada.buzz/invite/naddr1qvzqqqyzz5pzpverd527pyxx49f7hyk07t3wtwj9cm7zadg8suczsr7gymfygna2qqqqjm82js#BAADAQIDoL2AmVEk5T684eVCWeE8Qg)

> **Note**: this package is not yet listed in the official YunoHost app catalog, so it must be installed from this repository's URL rather than by name.

## Install

```bash
sudo yunohost app install https://github.com/imattau/yunohost-mcp-ynh
```

Or through the YunoHost admin web UI: **Applications → Install a custom app → From a Git repository**, using this repo's URL.

## Configuration

One install-time question:

| Setting | Description |
|---|---|
| **Your npub** | The Nostr public key granted the `administrator` role on install, so you aren't locked out of your own server. This same npub is also the server's **owner** — the identity that approves high-risk operations. |

See [`doc/ADMIN.md`](doc/ADMIN.md) for granting further identities access, adjusting safety policy, the audit trail, and owner approval; [`doc/PRE_INSTALL.md`](doc/PRE_INSTALL.md) for what you need before installing.

## Requirements

- A YunoHost server (packaging format 2, helpers 2.1 — YunoHost ≥ 12.1.17)
- Outbound network access to PyPI (build-time, to install Python dependencies)

## Packaging notes

- Python, not Node/Ruby/Go/Composer: there's no dedicated YunoHost resource for a Python virtualenv, so `scripts/_common.sh` creates one and `pip install`s the app into it directly from `pyproject.toml` on install/upgrade.
- **Runs as root**, not the app's own system user — see [`doc/ADMIN.md`](doc/ADMIN.md#a-privilege-note) for why, and what that does and doesn't mean for its actual security posture.
- No SSOwat/YunoHost-user auth on the app's own endpoint (`proxy_params_no_auth` in `conf/nginx.conf`) — this app authenticates its own callers via NIP-98, and SSOwat would otherwise intercept or rewrite the very `Authorization` header that scheme depends on.
- Persistent state (`identity.toml`, `policy.toml`, `revoked_delegations.toml`, `audit.jsonl`, and the server's own generated Nostr keypair) all live under the app's YunoHost-managed data directory, independent of `install_dir`'s upgrade-time wipe-and-replace.

Pull requests are welcome and should target `master`.

### 📚 App packaging documentation

See <https://doc.yunohost.org/packaging_apps> for more on YunoHost app packaging.
