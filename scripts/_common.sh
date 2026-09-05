#!/bin/bash
#=================================================
# PACKAGE-SPECIFIC HELPERS
#=================================================

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
		chown "$app:$app" "$f" 2>/dev/null || true
		chmod 600 "$f" 2>/dev/null || true
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
