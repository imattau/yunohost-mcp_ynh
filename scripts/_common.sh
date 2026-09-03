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
