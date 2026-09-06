#!/bin/bash
#=================================================
# PACKAGE-SPECIFIC HELPERS
#=================================================

# The Polypack package owns its YunoHost-allocated port. Keep the discovered
# endpoint in a separate EnvironmentFile so the optional integration can be
# refreshed without baking another app's port into this package's systemd
# template. An absent/unreadable Polypack app deliberately produces an empty
# file, which leaves the upstream setting at its safe "not configured" value.
yunohost_mcp_polypack_env_file() {
	echo "$data_dir/polypack.env"
}

yunohost_mcp_polypack_port() {
	local configured_port numeric_port
	configured_port="$(ynh_app_setting_get --app=polypack_mcp --key=port 2>/dev/null || true)"
	case "$configured_port" in
		''|*[!0-9]*) return 1 ;;
	esac
	numeric_port=$((10#$configured_port))
	if [ "$numeric_port" -lt 1 ] || [ "$numeric_port" -gt 65535 ]; then
		return 1
	fi
	printf '%s' "$numeric_port"
}

yunohost_mcp_set_polypack_endpoint() {
	local env_file port
	env_file="$(yunohost_mcp_polypack_env_file)"
	port="$(yunohost_mcp_polypack_port || true)"

	if [ -n "$port" ]; then
		printf 'YUNOHOST_MCP_POLYPACK_URL=http://127.0.0.1:%s/mcp/\n' "$port" > "$env_file"
		ynh_print_info "Polypack integration enabled at http://127.0.0.1:$port/mcp/"
	else
		printf '# Polypack MCP is optional and is not currently installed/configured.\n' > "$env_file"
		ynh_print_info "Polypack integration is not configured (optional app not detected)."
	fi

	chown "root:$app" "$env_file"
	chmod 640 "$env_file"
}

# Where the owner's NIP-46 pairing session (yunohost-mcp-approve's own
# app-channel keypair + reconnectable bunker:// URI - never the owner's
# real key) is persisted, shared between the optional install-time pairing
# step and every later config-panel pairing/approval action so they all
# reuse the same paired session instead of re-pairing each time.
yunohost_mcp_approve_session_file() {
	echo "$data_dir/approve-session.json"
}

# Where a pending, not-yet-consumed pairing offer (yunohost-mcp-approve
# offer's PendingOffer - a link/QR shown before anything is actually
# listening for the signer) is persisted, so it can be displayed
# immediately in the config panel and stays stable across page loads
# instead of regenerating on every view.
yunohost_mcp_approve_offer_file() {
	echo "$data_dir/approve-offer.json"
}

# Best-effort, optional pairing with the owner's NIP-46 signer app -
# offered at install time (see manifest.toml's pair_owner_signer_now) so
# owner approvals (system.upgrade, backup restore, ...) work out of the
# box, but never fatal to install: a signer that isn't ready yet, or an
# owner who'd rather do this later from the config panel, must not break
# setup. Prints the pairing link/QR to the live install log either way.
yunohost_mcp_pair_signer() {
	local owner_npub="$1"

	ynh_print_info "Pairing your NIP-46 signer for owner approvals - open the link/QR below in your signer app within the next couple of minutes..."
	if "$install_dir/venv/bin/yunohost-mcp-approve" pair \
		--session-file "$(yunohost_mcp_approve_session_file)" --offer-file "$(yunohost_mcp_approve_offer_file)" \
		--timeout 120 --owner-npub "$owner_npub"; then
		ynh_print_info "Signer paired - owner-approval operations (system.upgrade, backup restore, ...) can now be approved via yunohost-mcp-approve or the config panel."
	else
		# The offer isn't consumed on a timeout (only on success - see
		# approve.py's _pair), so the same link/QR just printed above stays
		# valid and the config panel's Owner approval section will keep
		# showing it - the owner can finish pairing there without this
		# ever needing to be redone from scratch.
		ynh_print_warn "Signer pairing did not complete within the install window - this is optional. The same link/QR shown above is still valid: finish pairing anytime from the config panel's Owner approval section (Apps > YunoHost MCP > Config panel), or by running yunohost-mcp-approve pair over SSH."
	fi
	for f in "$(yunohost_mcp_approve_session_file)" "$(yunohost_mcp_approve_offer_file)"; do
		[ -e "$f" ] || continue
		chown "root:$app" "$f" 2>/dev/null || true
		chmod 640 "$f" 2>/dev/null || true
	done
}

# Create the app's Python virtual environment and install yunohost-mcp
# (and its dependencies - mcp, coincurve, pydantic, ...) into it from the
# unpacked source tree in $install_dir. Runs as root (this package's own
# scripts run as root during install/upgrade; the resulting venv is then
# used by the systemd service, which also runs as root - see
# conf/systemd.service for why).
yunohost_mcp_install_venv() {
	# --system-site-packages: the yunohost Python package isn't pip-installable -
	# it's installed system-wide by moulinette/yunohost core (apt). Without this
	# flag the venv is fully isolated and every YunoHost-API-backed tool fails
	# with "ModuleNotFoundError: No module named 'yunohost'".
	python3 -m venv --system-site-packages "$install_dir/venv"
	ynh_hide_warnings "$install_dir/venv/bin/pip" install --upgrade pip
	ynh_hide_warnings "$install_dir/venv/bin/pip" install "$install_dir"
	# qrcode is an optional dependency of yunohost-mcp-approve upstream
	# (approve.py's _print_qr_if_available falls back to text-only without
	# it, silently) - installed explicitly here so the owner-approval
	# pairing flow (install's pair_owner_signer_now, and the config
	# panel's Pair action) actually shows a scannable QR code rather than
	# just a link, both of which this package relies on.
	ynh_hide_warnings "$install_dir/venv/bin/pip" install qrcode
}

# Seed identity.toml on first install with the admin's own npub as
# administrator. Without this, identity.toml starts empty and the server
# is deny-by-default for *everyone*, including the person who just
# installed it (PLAN.md Phase 3) - this is what makes a fresh install
# actually usable.
yunohost_mcp_seed_identity() {
	local npub="$1"

	cat > "$data_dir/identity.toml" <<EOF
[identity."$npub"]
name = "Initial administrator"
roles = ["administrator"]
EOF
	chown "$app:$app" "$data_dir/identity.toml"
	chmod 640 "$data_dir/identity.toml"
}

# The backend is shared by the unprivileged frontend and root broker through
# an EnvironmentFile, so a config-panel change cannot leave them using
# different authorization sources.
yunohost_mcp_set_identity_backend() {
	local backend="${1:-toml}"
	case "$backend" in
		toml|yunohost_groups) ;;
		*) ynh_die "Unknown identity backend: $backend" ;;
	esac
	printf 'YUNOHOST_MCP_IDENTITY_BACKEND=%s\n' "$backend" > "$data_dir/identity-backend.env"
	chown "$app:$app" "$data_dir/identity-backend.env"
	chmod 640 "$data_dir/identity-backend.env"
}

# The frontend is intentionally unprivileged.  Older releases ran it as root,
# so their runtime SQLite/audit files may still be root-owned; chmod() on an
# existing root-owned file fails after the privilege-boundary migration.
# Repair only files the frontend is expected to write, keeping identity and
# policy configuration outside this migration's write set.
yunohost_mcp_prepare_runtime_files() {
	local f
	# These are read by the frontend but remain administrator-owned.  The app
	# group provides read access without allowing the network-facing process to
	# rewrite authorization or policy configuration.
	for f in "$data_dir/identity.toml" "$data_dir/policy.toml" "$data_dir/revoked_delegations.toml"; do
		[ -e "$f" ] || continue
		chown "root:$app" "$f"
		chmod 640 "$f"
	done
	# The frontend lazily creates and refreshes this key, so it must own it;
	# it is still private to the app user.
	if [ -e "$data_dir/server_identity.key" ]; then
		chown "$app:$app" "$data_dir/server_identity.key"
		chmod 600 "$data_dir/server_identity.key"
	fi
	for f in "$data_dir/confirmations.sqlite" "$data_dir/audit.jsonl"; do
		[ -e "$f" ] || continue
		chown "$app:$app" "$f"
		chmod 660 "$f"
	done
	# SQLite may leave these sidecars behind after an interrupted shutdown.
	for f in "$data_dir/confirmations.sqlite-wal" "$data_dir/confirmations.sqlite-shm"; do
		[ -e "$f" ] || continue
		chown "$app:$app" "$f"
		chmod 660 "$f"
	done
}

# These groups are the YunoHost-side representation of MCP roles.  Keep them
# empty on creation: linking an identity and granting it a role are separate
# administrator decisions.
yunohost_mcp_ensure_scope_groups() {
	local group
	for group in \
		yunohost-mcp-readonly \
		yunohost-mcp-operator \
		yunohost-mcp-app-admin \
		yunohost-mcp-package-developer \
		yunohost-mcp-administrator; do
		if ! yunohost user group info "$group" >/dev/null 2>&1; then
			yunohost user group create "$group"
		fi
	done
}

# Print the MCP endpoint URL and this server's own Nostr identity (npub) at
# the end of install/upgrade/restore/change_url - without this, there is no
# other way to learn either value short of SSHing in and reading files, and
# the npub specifically is otherwise only obtainable by already being able
# to connect (the server_identity MCP tool) - a chicken-and-egg gap for
# anyone setting up delegation (PLAN.md Phase 11), which needs it.
#
# Call after the systemd service has (re)started: server_identity.key is
# generated at process startup (create_http_app() in the upstream repo),
# before the service accepts connections, so it's guaranteed to exist by
# the time ynh_systemctl's --wait_until returns.
yunohost_mcp_print_connection_info() {
	local target_domain="$1"

	ynh_print_info "MCP endpoint: https://$target_domain/mcp"

	local npub
	npub="$("$install_dir/venv/bin/python3" -c "
from pathlib import Path
from yunohost_mcp.auth.server_identity import ServerIdentity
print(ServerIdentity.load_or_generate(Path('$data_dir/server_identity.key')).npub)
" 2>/dev/null)" || true

	if [ -n "$npub" ]; then
		ynh_print_info "Server identity (npub): $npub - a delegation naming this server must use this exact value"
	else
		ynh_print_warn "Could not read the server's own npub here - call the server_identity MCP tool, or see doc/ADMIN.md"
	fi
}
