## Before you install

You'll need a Nostr keypair (any Nostr client — a browser extension like nos2x/Alby, a mobile app, or `nostr-tools`/similar for a fresh one works) and its **npub** (public key). This install form asks for it and grants it the `administrator` role, so the account that just installed the server isn't immediately locked out — `identity.toml` starts out empty otherwise, and this server denies everything by default until an identity is explicitly granted access.

Your **private** key never needs to touch this server. The npub you give here is a public identity, not a secret.

## Domain

This app is installed at the root of a domain (no custom path) — an MCP client connects to `https://your-domain/mcp`.

## What this actually does once installed

This is not a web app you browse. It's an API endpoint an MCP-capable AI client connects to directly, authenticating each request with a Nostr signature. See `doc/ADMIN.md` after install for how to grant further identities access, and for an important note about the privilege level this service runs at.

## Your MCP client needs to support NIP-98

Mainstream MCP clients (Claude Desktop, a plain Codex CLI install, etc.) don't sign requests with a Nostr key out of the box — that's specific to this server. You'll need a client, wrapper, or proxy that can attach a [NIP-98](https://github.com/nostr-protocol/nips/blob/master/98.md) `Authorization: Nostr ...` header signed with your own key to every request. If you don't already have one, install this only once you know what you're connecting with.
