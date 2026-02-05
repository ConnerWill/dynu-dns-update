#!/usr/bin/env bash
# Dynu DDNS auto-updater with functions
# Skips IPv6 if unavailable
# Avoids env var conflicts and supports cron
# Includes lockfile and IPv4 check
# ---------------------------
set -euo pipefail
IFS=$'\n\t'

# ---------------------------
# VARIABLES
# ---------------------------
CONFIG_FILE_DIR="${CONFIG_FILE_DIR:-${XDG_CONFIG_HOME:-${HOME}/.config}/dynu-ddns-update}"
CONFIG_FILE="${CONFIG_FILE:-${CONFIG_FILE_DIR}/dynu_ddns.conf}"
LOG_DIR_DEFAULT="${XDG_STATE_HOME:-${HOME}/.local/state}/dynu-ddns"
LOG_FILE_DEFAULT="${LOG_FILE:-${LOG_DIR_DEFAULT}/dynu-ddns-update.log}"
LOCK_FILE="${LOCK_FILE:-/var/tmp/dynu_ddns.lock}"
STATE_FILE_DEFAULT="${STATE_FILE:-/var/tmp/dynu_ddns_state}"
CURL_OPTIONS=(
    --silent        # silent mode
    --show-error    # show errors
    --fail          # exit with non-zero if HTTP status >= 400
    --max-time 10   # 10-second timeout
)

# -----------------------------------------------
# LOGGING
# -----------------------------------------------
log_init() {
  mkdir -p "$(dirname "${LOG_FILE}")"
  touch "${LOG_FILE}"
  chmod 600 "${LOG_FILE}"
}

log() {
  local level current_date
  level="${1}"
  shift
  current_date="$(date '+%Y-%m-%d %H:%M:%S')"
  printf '%s [%s] %s\n' "${current_date}" "${level}" "${*}" >> "${LOG_FILE}"
}

success() { log SUCCESS "${*}"; }
info()    { log INFO    "${*}"; }
warn()    { log WARN    "${*}"; }
error()   { log ERROR   "${*}"; }

# ---------------------------
# CONFIG FILE
# ---------------------------
create_config() {
  if [[ ! -d "${CONFIG_FILE_DIR}" ]]; then
    mkdir -p "${CONFIG_FILE_DIR}" || { echo "Unable to create config directory: ${CONFIG_FILE_DIR}"; exit 1; }
    echo "Created configuration directory: ${CONFIG_FILE_DIR}"
  fi

  if [[ ! -f "${CONFIG_FILE}" ]]; then
    cat <<EOF > "${CONFIG_FILE}"
## ${CONFIG_FILE}

# dynu.com username
DYNU_USERNAME="${DYNU_USERNAME:-your_username_here}"

# dynu.com password (plain text or MD5/SHA256 hash)
DYNU_PASSWORD="${DYNU_PASSWORD:-your_password_here}"

# Dynamic DNS Domain (comma-separated if multiple)
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
    echo "Created example config file: ${CONFIG_FILE}"
    echo "Please edit the config file with your values."
    exit 0
  else
    info "Config file already exists, not overwriting:"
    info "  ${CONFIG_FILE}"
  fi
}

if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "❌ Config file not found: '${CONFIG_FILE}'"
    create_config
fi

# Load config variables
# shellcheck disable=SC1090
source "${CONFIG_FILE}" || { error "Unable to source config file: ${CONFIG_FILE}"; exit 1; }

STATE_FILE="${STATE_FILE:-${STATE_FILE_DEFAULT}}"
LOG_FILE="${LOG_FILE:-${LOG_FILE_DEFAULT}}"

log_init
info "=== Dynu DDNS run started ==="

# ---------------------------
# FUNCTIONS
# ---------------------------
get_base_url() {
  if ${USE_SSL}; then
    echo "https://api.dynu.com/nic/update"
  else
    echo "http://api.dynu.com/nic/update"
  fi
}

get_current_ipv4() {
  local ip
  ip=$(curl "${CURL_OPTIONS[@]}" 'https://api.ipify.org' || echo "")
  echo "${ip}"
}

get_current_ipv6() {
  local ip
  ip=$(curl "${CURL_OPTIONS[@]}" 'https://api64.ipify.org' || echo "")
  if [[ "${ip}" == *:* ]]; then
    echo "${ip}"
  else
    echo ""  # Skip IPv6 if not available
  fi
}

read_last_ips() {
  local last_ipv4 last_ipv6
  if [[ -f "${STATE_FILE}" ]]; then
    last_ipv4=$(grep '^IPV4=' "${STATE_FILE}" | cut -d'=' -f2- || echo "")
    last_ipv6=$(grep '^IPV6=' "${STATE_FILE}" | cut -d'=' -f2- || echo "")
  else
    last_ipv4=""
    last_ipv6=""
  fi
  echo "${last_ipv4}" "${last_ipv6}"
}

save_current_ips() {
  local ipv4="${1}" ipv6="${2}"
  mkdir -p "$(dirname "${STATE_FILE}")"
  cat > "${STATE_FILE}" <<EOF
IPV4=${ipv4}
IPV6=${ipv6}
EOF
}

build_update_url() {
  local base="${1}" ipv4="${2}" ipv6="${3}"
  local url="${base}?hostname=${DYNU_HOSTNAME}&myip=${ipv4}&password=${DYNU_PASSWORD}"
  [[ -n "${ipv6}" ]] && url+="&myipv6=${ipv6}" || url+="&myipv6=no"
  echo "${url}"
}

send_update_request() {
  local url="${1}"
  curl "${CURL_OPTIONS[@]}" "${url}"
}

handle_response() {
  local response="${1}"
  case "${response}" in
    good*)        success "IP update successful: ${response}" ;;
    nochg*)       info    "IP unchanged: ${response}" ;;
    badauth*)     error   "Authentication failed: ${response}" ;;
    nohost*)      error   "Hostname not found: ${response}" ;;
    notfqdn*)     error   "Invalid hostname: ${response}" ;;
    numhost*)     error   "Too many hostnames specified: ${response}" ;;
    abuse*)       error   "Abuse detected: ${response}" ;;
    dnserr*)      error   "Server DNS error: ${response}" ;;
    servererror*) error   "Server error: ${response}" ;;
    911*)         warn    "Server maintenance: ${response}" ;;
    *)            warn    "Unknown response: ${response}" ;;
  esac
}

# ---------------------------
# MAIN SCRIPT
# ---------------------------
main() {
  local ipv4 ipv6 last_ipv4 last_ipv6 base_url update_url response

  # Lock to prevent overlapping runs
  exec 200>"${LOCK_FILE}"
  if flock -n 200; then
    warn "Another instance is running. Exiting."
    exit 0
  fi

  # Get current IPs
  ipv4=$(get_current_ipv4)
  ipv6=$(get_current_ipv6)

  # Check if IPv4 is empty
  if [[ -z "${ipv4}" ]]; then
    error "Unable to determine current IPv4 address"
    exit 1
  fi

  # Get last IPs
  read last_ipv4 last_ipv6 <<< "$(read_last_ips)"

  # Display current and previous IPs
  info "Current IPs: IPv4=${ipv4}, IPv6=${ipv6:-none}"
  info "Last IPs:    IPv4=${last_ipv4:-none}, IPv6=${last_ipv6:-none}"

  # Check if current IP matches previous IP
  if [[ "${ipv4}" == "${last_ipv4}" && "${ipv6}" == "${last_ipv6}" ]]; then
    info "No IP change detected - no update needed"
    exit 0
  fi

  # Build URL
  base_url=$(get_base_url)
  update_url=$(build_update_url "${base_url}" "${ipv4}" "${ipv6}")


  # Update DYNU DDNS entry
  info "IP change detected. Updating Dynu DDNS for ${DYNU_HOSTNAME}..."
  response=$(send_update_request "${update_url}")

  # Handle response
  handle_response "${response}"

  # Save current IPs
  save_current_ips "${ipv4}" "${ipv6}"

  info "Dynu DDNS state updated: ${DYNU_HOSTNAME}"
}

main

info "=== Dynu DDNS run finished ==="
