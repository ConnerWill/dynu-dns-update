#!/usr/bin/env bash
# Install script for dynu-ddns updater
set -euo pipefail
IFS=$'\n\t'

# ---------------------------
# CONFIG
# ---------------------------
SCRIPT_NAME="dynu-ddns-update.sh"
INSTALL_DIR="/usr/local/bin"
INSTALL_PATH="${INSTALL_DIR}/${SCRIPT_NAME}"
CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/dynu-ddns-update"
CONFIG_FILE="${CONFIG_DIR}/dynu_ddns.conf"
SCRIPT_MODE="0755"

# ---------------------------
# FUNCTIONS
# ---------------------------
die() {
  printf "❌ %s\n" "${1}" >&2
  exit 1
}

info() {
  printf "ℹ  %s\n" "${1}"
}

success() {
  printf "✅ %s\n" "${1}"
}

require_install() {
  command -v install >/dev/null 2>&1 || die "'install' command not found"
}

require_script() {
  [[ -f "${SCRIPT_NAME}" ]] || die "Script '${SCRIPT_NAME}' not found in current directory"
}

# ---------------------------
# MAIN
# ---------------------------
main() {
  require_install
  require_script

  info "Installing '${SCRIPT_NAME}' to '${INSTALL_PATH}'"

  sudo install -D           \
    --mode "${SCRIPT_MODE}" \
    "${SCRIPT_NAME}"        \
    "${INSTALL_PATH}" && { success "Script installed to '${INSTALL_PATH}'"; }

  if [[ ! -f "${CONFIG_FILE}" ]]; then
    info "Config file not found, creating initial config"
    mkdir -p "${CONFIG_DIR}"

    cat <<EOF > "${CONFIG_FILE}"
## ${SCRIPT_NAME}
## ${CONFIG_FILE}

# dynu.com username
DYNU_USERNAME="${DYNU_USERNAME:-your_username_here}"

# dynu.com password (plain text or MD5/SHA256 hash)
DYNU_PASSWORD="${DYNU_PASSWORD:-your_password_here}"

# Dynamic DNS Domain
DYNU_HOSTNAME="${DYNU_HOSTNAME:-example.dynu.com}"

# Use SSL/HTTPS
USE_SSL=${USE_SSL:-true}

# Path to log file
LOG_FILE="${LOG_FILE:-${XDG_STATE_HOME:-${HOME}/.local/state}/dynu-ddns/dynu-ddns-update.log}"

# Path to cron-safe state file
STATE_FILE="${STATE_FILE:-/var/tmp/dynu_ddns_state}"

#vim:filetype=conf:shiftwidth=2:softtabstop=2:expandtab
EOF

    chmod 600 "${CONFIG_FILE}"
    success "Created config file at ${CONFIG_FILE}"
    info "Please edit this file before enabling cron"
  else
    info "Config file already exists, not overwriting: '${CONFIG_FILE}'"
  fi

  cat <<EOF

Next steps:
  1) Edit your config:
     \$ ${EDITOR:-vim} ${CONFIG_FILE}

  2) Test the script manually:
     \$ ${INSTALL_PATH}

  3) Add to cron (example: every 10 minutes):
     \$ cron -e

     */10 * * * * ${INSTALL_PATH}

EOF
}

main
