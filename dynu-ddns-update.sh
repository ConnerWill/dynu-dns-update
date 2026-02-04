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
CURL_OPTIONS=(
    --silent        # silent mode
    --show-error    # show errors
    --fail          # exit with non-zero if HTTP status >= 400
    --max-time 10   # 10-second timeout
)

# Lockfile to prevent overlapping runs
LOCK_FILE="/var/tmp/dynu_ddns.lock"

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

# Path to cron-safe state file
STATE_FILE="${STATE_FILE:-/var/tmp/dynu_ddns_state}"

#vim:filetype=conf:shiftwidth=2:softtabstop=2:expandtab
EOF
    echo "Created example config file: ${CONFIG_FILE}"
    echo "Please edit the config file with your values."
    exit 0
  fi
}

if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "❌ Config file not found: '${CONFIG_FILE}'"
    create_config
fi

# Load config variables
# shellcheck disable=SC1090
source "${CONFIG_FILE}" || { echo "Unable to source config file: ${CONFIG_FILE}"; exit 1; }

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
  if [[ -n "${ipv6}" ]]; then
    url="${url}&myipv6=${ipv6}"
  else
    url="${url}&myipv6=no"
  fi
  echo "${url}"
}

send_update_request() {
  local url="${1}"
  curl "${CURL_OPTIONS[@]}" "${url}"
}

handle_response() {
  local response="${1}"
  case "${response}" in
    good*) echo "✅ IP update successful: ${response}" ;;
    nochg*) echo "ℹ IP unchanged: ${response}" ;;
    badauth*) echo "❌ Authentication failed: ${response}" ;;
    nohost*) echo "❌ Hostname not found: ${response}" ;;
    notfqdn*) echo "❌ Invalid hostname: ${response}" ;;
    numhost*) echo "❌ Too many hostnames specified: ${response}" ;;
    abuse*) echo "❌ Abuse detected: ${response}" ;;
    dnserr*) echo "❌ Server DNS error: ${response}" ;;
    servererror*) echo "❌ Server error: ${response}" ;;
    911*) echo "⏸ Server maintenance: ${response}. Retry after 10 minutes." ;;
    *) echo "⚠ Unknown response: ${response}" ;;
  esac
}

# ---------------------------
# MAIN SCRIPT
# ---------------------------
main() {
  # Lock to prevent overlapping runs
  exec 200>"${LOCK_FILE}"
  flock -n 200 || { echo "Another instance is running. Exiting."; exit 0; }

  local ipv4 ipv6 last_ipv4 last_ipv6 base_url update_url response

  ipv4=$(get_current_ipv4)
  if [[ -z "${ipv4}" ]]; then
    echo "❌ Unable to determine current IPv4 address. Exiting."
    exit 1
  fi

  ipv6=$(get_current_ipv6)
  read last_ipv4 last_ipv6 <<< "$(read_last_ips)"

  if [[ "${ipv4}" == "${last_ipv4}" && "${ipv6}" == "${last_ipv6}" ]]; then
    echo "No IP change detected. Dynu update not required."
    exit 0
  fi

  base_url=$(get_base_url)
  update_url=$(build_update_url "${base_url}" "${ipv4}" "${ipv6}")
  echo "IP change detected. Updating Dynu DDNS for ${DYNU_HOSTNAME}..."
  response=$(send_update_request "${update_url}")

  handle_response "${response}"
  save_current_ips "${ipv4}" "${ipv6}"
  echo "✅ Dynu DDNS state updated."
}

main
