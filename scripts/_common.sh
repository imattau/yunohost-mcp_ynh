#!/bin/bash
#=================================================
# PACKAGE-SPECIFIC HELPERS
#=================================================

# Create the app's Python virtual environment and install yunohost-mcp
# (and its dependencies - mcp, coincurve, pydantic, ...) into it from the
# unpacked source tree in $install_dir. Runs as root (this package's own
# scripts run as root during install/upgrade; the resulting venv is then
# used by the systemd service, which also runs as root - see
# conf/systemd.service for why).
yunohost_mcp_install_venv() {
	python3 -m venv "$install_dir/venv"
	ynh_hide_warnings "$install_dir/venv/bin/pip" install --upgrade pip
	ynh_hide_warnings "$install_dir/venv/bin/pip" install "$install_dir"
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
