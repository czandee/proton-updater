#!/bin/bash
# Updates the debian packages provided by Proton Apps like
# ProtonPass and ProtonMail.
# See usage() or update-proton --help

APPNAME="$(basename "$0")"

# defaults for the CLI options
DOWNLOAD_DIR="$HOME/Downloads"
VERBOSE="${VERBOSE-"false"}"
VERIFY_SSL="${VERIFY_SSL-"true"}"
DRY_RUN="${DRY_RUN-"false"}"
VERSION="1.2.0"

# configuration for the meta urls in json format
declare -A JSON_URLS=(
  ["pass"]="https://proton.me/download/PassDesktop/linux/x64/version.json"
  ["mail"]="https://proton.me/download/mail/linux/version.json"
)
declare -A PACKAGES=(
  ["pass"]="proton-pass"
  ["mail"]="proton-mail"
)

# safety and strict mode
set -euo pipefail

# show usage information
function usage() {
  cat <<EOF
Update a Proton Desktop App.

Usage: ${APPNAME} [OPTIONS] package

package:
  pass              Update Proton Pass
  mail              Update Proton Mail

OPTIONS:
  -d, --directory   Local directory to use as download location.
                    Default: ${DOWNLOAD_DIR}
  -n, --no-verify   Disable SSL certificate verification (not recommended)
  -y, --dry-run     Check for updates without downloading or installing
  -v, --verbose     Log debug messages.
  --version         Show version information
  -h, --help        Show this usage information.

EOF
}

# simple logging functions, use VERBOSE=true or CLI option -v for debugging out
function log_debug { if [[ "$VERBOSE" == "true" ]]; then printf "%s %-7s $1\n" "$APPNAME" "[debug]" "${@:2}"; fi; }
function log_info { printf "%s %-7s $1\n" "$APPNAME" "[info]" "${@:2}"; }
function log_warning { printf "%s %-7s $1\n" "$APPNAME" "[warn]" "${@:2}"; }
function log_error { printf "%s %-7s $1\n" "$APPNAME" "[error]" "${@:2}"; }

# Check Dependencies
# $*: commands to check for existance
function check_dependencies {
  local dependencies=("${@}")
  for cmd in "${dependencies[@]}"; do
    if ! command -v "$cmd" > /dev/null 2>&1; then
      log_error "Missing required dependency: $cmd"
      log_error "Please install it (e.g. sudo apt install $cmd)"
      exit 1
    fi
  done
}

# command line parsing
# $*: command line to parse
function parse_args {
  local short="d:nvy:h"
  local long="directory:,no-verify,dry-run,verbose,version,help"

  local rc
  getopt -T >/dev/null 2>&1 && rc=$? || rc=$?
  local args
  if [[ $rc -eq 4 ]]; then
    args=$(getopt --options "$short" --long "$long" --name "$0" -- "$@") || {
      usage
      exit 1
    }
  else
    log_error "No GNU getopt, reduced support for short options only"
    args=$(getopt $short "$@") || {
      usage
      exit 1
    }
  fi
  # reset command line arguments to the getopt parsing result
  eval set -- "$args"

  while true; do
    case "$1" in
      -h|--help) usage; exit 0;;
      --version) echo "${APPNAME} version ${VERSION}"; exit 0;;
      -d|--directory) DOWNLOAD_DIR="${2}"; shift 2;;
      -n|--no-verify) VERIFY_SSL="false"; shift;;
      -y|--dry-run) DRY_RUN="true"; shift;;
      -v|--verbose) VERBOSE="true"; shift;;
      --) shift; break;; # end of options, the rest will be passed through
      *) usage; exit 0;;
    esac
  done

  local positional_args=("$@")
  if [[ ${#positional_args[@]} -ne 1 ]]; then
    log_error "Exactly one positional argument required."
    usage
    exit 1
  fi

  local action="${positional_args[0]}"
  if [[ -n "${JSON_URLS[$action]:-}" ]]; then
    JSON_URL="${JSON_URLS[$action]}"
    PACKAGE_NAME="${PACKAGES[$action]}"
    log_debug "Selected action: $action (Package: $PACKAGE_NAME)"
  else
    log_error "Invalid action: '$action'. Allowed values: ${!JSON_URLS[*]}"
    usage
    exit 1
  fi
}

# Main updater function
# $1: package-name
# $2: url for the version information (json file)
# $3: download directory for the debian package
# $4: optional: validate sudo (true/false, default: false)
# $5  optional: retry count on wget download problems (default: 3)
# $6: optional: cleanup after install (true/false, default: true)
function update_proton {
  local package_name=$1
  local json_url=$2
  local download_dir=$3
  local validate_sudo="${4-"false"}"
  local retry_count="${5-3}"
  local cleanup_after_install="${6-"true"}"

  log_info "Updater for $package_name started"

  # sudo refresh (optional, not required if you have sudo privs with NOPASSWD)
  if [[ "$validate_sudo" == "true" ]]; then
    log_debug "Refreshing sudo credentials..."
    if ! sudo -v; then
      log_error "Sudo privileges required to install packages."
      exit 1
    fi
  fi

  local curl_ssl_arg=""
  if [[ "$VERIFY_SSL" != "true" ]]; then
    curl_ssl_arg="-k"
  fi

  log_info "Fetching latest version info..."

  # fetch JSON content
  local json_content
  json_content=$(curl $curl_ssl_arg -s -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64)" "$json_url")

  if [ -z "$json_content" ]; then
    log_error "Server returned no data."
    exit 1
  fi

  # extract package and version data
  # use subshell and capturing to avoid pipefail issues in variable assignment
  local read_data
  read_data=$(echo "$json_content" | jq -r '
    .Releases[0] |
    {Version: .Version, File: (.File[] | select(.Identifier | contains(".deb")))} |
    "\(.Version) \(.File.Sha512CheckSum) \(.File.Url)"
  ')

  local latest_version
  local checksum
  local deb_url
  read -r latest_version checksum deb_url <<< "$read_data"
  local file_name
  file_name="$(basename "$deb_url")"

  log_debug "Most recent online version: $latest_version"
  log_debug "Filename: $deb_url"

  if [ -z "$checksum" ] || [ "$checksum" == "null" ]; then
    log_error "Could not extract data from JSON."
    exit 1
  fi

  # idempotency check (version comparison)
  # SC2086: We quote the variables to prevent word splitting
  local installed_version
  installed_version=$(dpkg-query -W -f='${Version}' "$package_name" 2>/dev/null || true)

  if [ "$installed_version" == "$latest_version" ]; then
    log_info "$package_name is already up to date (Version $installed_version)."
    exit 0
  else
    if [ -z "$installed_version" ]; then
      log_info "$package_name is not installed. Preparing version $latest_version."
    else
      log_info "Update available: $installed_version -> $latest_version"
    fi
    log_debug "Checksum: $checksum"
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[dry-run] Would download: $deb_url"
    log_info "[dry-run] Would install: $file_name"
    exit 0
  fi

  # prepare download
  if [[ ! -d "${download_dir}" ]]; then
    log_info "Creating $download_dir"
    mkdir -p "${download_dir}"
  fi

  pushd "${download_dir}" > /dev/null || exit 1
  # SC2064: Use single quotes to ensure trap is evaluated at exit time, not definition time
  trap 'popd > /dev/null' EXIT

  # local cache check
  local file_already_valid=false
  if [ -f "$file_name" ]; then
    log_debug "File $file_name exists. Checking integrity..."
    if echo "$checksum  $file_name" | sha512sum --check --status 2>/dev/null; then
      log_info "Local file valid. Skipping download."
      file_already_valid=true
    else
      log_info "Local file hash mismatch. Re-downloading."
      rm -f "$file_name"
    fi
  fi

  local wget_ssl_arg=""
  if [[ "$VERIFY_SSL" != "true" ]]; then
    wget_ssl_arg="--no-check-certificate"
  fi

  # download (with retries)
  if [ "$file_already_valid" == "false" ]; then
    log_info "Downloading $file_name..."
    # -t: retries, -T: timeout
    if ! wget -t "$retry_count" -T 15 -U "Mozilla/5.0" $wget_ssl_arg -q --show-progress -O "$file_name" "$deb_url"; then
      log_error "Download failed after $retry_count attempts."
      exit 1
    fi

    log_info "Verifying Checksum..."
    if ! echo "$checksum  $file_name" | sha512sum --check -; then
      log_error "Check FAILED. File corrupt."
      exit 1
    fi
  fi

  # installation with fallback
  log_info "Installing $file_name..."
  if sudo dpkg -i "$file_name"; then
    log_info "Installation successful."
  else
    log_info "dpkg failed. Attempting to fix missing dependencies..."

    # Attempt to fix broken dependencies (common with .deb files)
    if sudo apt-get update && sudo apt-get install -f -y; then
      log_info "Dependencies fixed and installation completed."
    else
      log_error "Installation failed even after dependency fix."
      exit 1
    fi
  fi

  # optional cleanup
  [[ "${cleanup_after_install}" == "true" ]] && {
    log_debug "Cleaning up: Removing $file_name"
    rm -f "$file_name"
  }
  log_info "Process for $package_name complete."
}

# main
check_dependencies "curl" "jq" "wget" "sha512sum" "dpkg" "sudo"
parse_args "$@" # returns PACKAGE_NAME, JSON_URL and DOWNLOAD_DIR
update_proton "$PACKAGE_NAME" "$JSON_URL" "$DOWNLOAD_DIR"
