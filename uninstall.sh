#!/usr/bin/env bash
#shellcheck disable=2154
# Uninstall script for dynu-ddns updater
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

  info "Uninstalling ${SCRIPT_NAME} from ${INSTALL_PATH}"

  if [[ -e "${INSTALL_PATH}" ]]; then
    sudo rm -f "${INSTALL_PATH}" || { info "Unable to remove '${SCRIPT_NAME}' from '${INSTALL_PATH}'"; }
  else
    info "Cannot find '${SCRIPT_NAME}' at location: '${INSTALL_PATH}'"
  fi

  if [[ -e "${CONFIG_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${CONFIG_FILE}" || { die "Unable to source configuration file: '${CONFIG_FILE}' to gather file locations."; }
    info "Configuration file still exists, skipping automatic removal of configuration file: '${CONFIG_FILE}'"
  fi

  if [[ -e "${LOG_FILE}" ]]; then
    info "Removing log file: '${LOG_FILE}'"
    rm -f "${LOG_FILE}" || { info "Unable to remove log file: '${LOG_FILE}'"; }
  else
    info "Cannot find log file: '${LOG_FILE}'"
  fi

  if [[ -e "${STATE_FILE}" ]]; then
    info "Removing state file: '${STATE_FILE}'"
    rm -f "${STATE_FILE}" || { info "Unable to remove state file: '${STATE_FILE}'"; }
  else
    info "Cannot find state file: '${STATE_FILE}'"
  fi

}

main
