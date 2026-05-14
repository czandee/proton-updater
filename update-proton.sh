#!/bin/bash
# Updates the debian packages provided by Proton Apps like
# ProtonPass and ProtonMail.
# See usage() or update-proton --help

# safety and strict mode
set -euo pipefail

APPNAME="$(basename "$0")"

# default values for the CLI options (can be overridden by environment)
# environment variables set to "" will result in using the default
DOWNLOAD_DIR="$HOME/Downloads"
VERBOSE="${VERBOSE:-"false"}"
VERIFY_SSL="${VERIFY_SSL:-"true"}"
DRY_RUN="${DRY_RUN:-"false"}"
RETRY_COUNT="${RETRY_COUNT:-3}"
CLEANUP="${CLEANUP:-"true"}"
readonly VERSION="1.4.0"
readonly PASS_CLI_VERSION_URL="https://proton.me/download/pass-cli/versions.json"
PASS_CLI_INSTALL_DIR="${PASS_CLI_INSTALL_DIR:-$HOME/.local/bin}"
ACTION=""

# configuration for the meta urls in json format
declare -rA JSON_URLS=(
  ["pass"]="https://proton.me/download/PassDesktop/linux/x64/version.json"
  ["mail"]="https://proton.me/download/mail/linux/version.json"
)
declare -rA PACKAGES=(
  ["pass"]="proton-pass"
  ["mail"]="proton-mail"
)

# show usage information
function usage {
  cat <<EOF
Update a Proton Desktop App.

Usage: ${APPNAME} [OPTIONS] package

package:
  pass              Update Proton Pass
  mail              Update Proton Mail
  cli               Update Proton Pass CLI

OPTIONS:
  -d, --directory   Local directory to use as download location (deb packages).
                    Default: ${DOWNLOAD_DIR}
  -i, --install-dir Install directory for the pass-cli binary.
                    Default: ${PASS_CLI_INSTALL_DIR}
                    Can also be set via PASS_CLI_INSTALL_DIR env var.
  -n, --no-verify   Disable SSL certificate verification (not recommended)
  -y, --dry-run     Check for updates without downloading or installing
  -v, --verbose     Log debug messages.
  --version         Show version information
  -h, --help        Show this usage information.

EOF
}

# simple logging functions, use VERBOSE=true or CLI option -v for debugging out
function log_debug   { if [[ "$VERBOSE" == "true" ]]; then printf "%s %-7s %s\n" "$APPNAME" "[debug]" "$1" >&2; fi; }
function log_info    { printf "%s %-7s %s\n" "$APPNAME" "[info]" "$1"; }
function log_warning { printf "%s %-7s %s\n" "$APPNAME" "[warn]" "$1" >&2; }
function log_error   { printf "%s %-7s %s\n" "$APPNAME" "[error]" "$1" >&2; }

# Fetch JSON from a URL, respecting VERIFY_SSL. Exits on HTTP errors or empty response.
function fetch_json {
  local url=$1
  local curl_ssl_opts=()
  [[ "$VERIFY_SSL" != "true" ]] && curl_ssl_opts+=("-k")
  local content
  content=$(curl -f "${curl_ssl_opts[@]}" -s -m 30 -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64)" "$url")
  if [[ -z "$content" ]]; then
    log_error "Server returned no data."
    exit 1
  fi
  echo "$content"
}

# Download a file with retries, respecting VERIFY_SSL. Exits on failure.
# $1: output file path
# $2: URL to download
function download_file {
  local output=$1
  local url=$2
  local curl_ssl_opts=()
  [[ "$VERIFY_SSL" != "true" ]] && curl_ssl_opts+=("-k")
  if ! curl -f --retry "$RETRY_COUNT" --connect-timeout 15 -A "Mozilla/5.0" "${curl_ssl_opts[@]}" --progress-bar -o "$output" "$url"; then
    log_error "Download failed after $RETRY_COUNT attempts."
    exit 1
  fi
}

# Check Dependencies
# $*: commands to check for existence
function check_dependencies {
  local missing=()
  for cmd in "$@"; do
    if ! command -v "$cmd" > /dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "Missing required dependencies: ${missing[*]}"
    log_error "Please install them (e.g. sudo apt install ${missing[*]})"
    exit 1
  fi
}

# command line parsing
# $*: command line to parse
function parse_args {
  local short="d:i:nvyh"
  local long="directory:,install-dir:,no-verify,verbose,dry-run,version,help"

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
    args=$(getopt "$short" "$@") || {
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
      -i|--install-dir) PASS_CLI_INSTALL_DIR="${2}"; shift 2;;
      -n|--no-verify) VERIFY_SSL="false"; shift;;
      -y|--dry-run) DRY_RUN="true"; shift;;
      -v|--verbose) VERBOSE="true"; shift;;
      --) shift; break;; # end of options, the rest will be passed through
      *) usage; exit 1;;
    esac
  done

  local positional_args=("$@")
  if [[ ${#positional_args[@]} -ne 1 ]]; then
    log_error "Exactly one positional argument required."
    usage
    exit 1
  fi

  local action="${positional_args[0]}"
  if [[ "$action" == "cli" ]]; then
    ACTION="cli"
    log_debug "Selected action: cli (pass-cli binary)"
  elif [[ -n "${JSON_URLS[$action]:-}" ]]; then
    ACTION="$action"
    JSON_URL="${JSON_URLS[$action]}"
    PACKAGE_NAME="${PACKAGES[$action]}"
    log_debug "Selected action: $action (Package: $PACKAGE_NAME)"
  else
    log_error "Invalid action: '$action'. Allowed values: ${!JSON_URLS[*]} cli"
    usage
    exit 1
  fi
}

# Updater for the pass-cli standalone binary
# $1: install directory for the binary
function update_pass_cli {
  local install_dir=$1

  log_info "Updater for pass-cli started"

  local arch
  arch=$(uname -m)
  if [[ "$arch" != "x86_64" && "$arch" != "aarch64" ]]; then
    log_error "Unsupported architecture: $arch"
    exit 1
  fi

  log_info "Fetching latest version info..."
  local json_content
  json_content=$(fetch_json "$PASS_CLI_VERSION_URL")

  local latest_version download_url checksum
  latest_version=$(echo "$json_content" | jq -r '.passCliVersions.version')
  download_url=$(echo "$json_content" | jq -r ".passCliVersions.urls.linux.${arch}.url")
  checksum=$(echo "$json_content" | jq -r ".passCliVersions.urls.linux.${arch}.hash")

  if [[ -z "$latest_version" || "$latest_version" == "null" ||
        -z "$checksum"       || "$checksum"       == "null" ||
        -z "$download_url"   || "$download_url"   == "null" ]]; then
    log_error "Could not extract data from JSON."
    exit 1
  fi

  log_debug "Most recent online version: $latest_version"
  log_debug "Download URL: $download_url"

  local installed_version=""
  local pass_cli_bin="$install_dir/pass-cli"
  if [[ ! -x "$pass_cli_bin" ]]; then
    pass_cli_bin=$(command -v pass-cli 2>/dev/null || true)
  fi
  if [[ -n "$pass_cli_bin" ]]; then
    installed_version=$("$pass_cli_bin" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
  fi

  if [[ "$installed_version" == "$latest_version" ]]; then
    log_info "pass-cli is already up to date (Version $installed_version)."
    exit 0
  fi

  if [[ -z "$installed_version" ]]; then
    log_info "pass-cli is not installed. Preparing version $latest_version."
  else
    log_info "Update available: $installed_version -> $latest_version"
  fi
  log_debug "Checksum (sha256): $checksum"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[dry-run] Would download: $download_url"
    log_info "[dry-run] Would install to: $install_dir/pass-cli"
    exit 0
  fi

  if [[ ! -d "$install_dir" ]]; then
    log_info "Creating $install_dir"
    mkdir -p "$install_dir"
  fi

  local tmp_file
  tmp_file=$(mktemp)
  # shellcheck disable=SC2064
  trap "rm -f '$tmp_file'" EXIT

  log_info "Downloading pass-cli $latest_version..."
  download_file "$tmp_file" "$download_url"

  log_info "Verifying checksum..."
  if ! echo "$checksum  $tmp_file" | sha256sum --check --status; then
    log_error "Checksum verification FAILED. File corrupt."
    exit 1
  fi

  chmod +x "$tmp_file"
  mv "$tmp_file" "$install_dir/pass-cli"
  log_info "Installed pass-cli $latest_version to $install_dir/pass-cli"
  log_info "Process for pass-cli complete."
}

# Main updater function
# $1: package-name
# $2: url for the version information (json file)
# $3: download directory for the debian package
function update_proton {
  local package_name=$1
  local json_url=$2
  local download_dir=$3

  log_info "Updater for $package_name started"

  local arch
  arch=$(uname -m)
  if [[ "$arch" != "x86_64" ]]; then
    log_error "Unsupported architecture: $arch. Only x86_64 is supported."
    exit 1
  fi

  log_info "Fetching latest version info..."
  local json_content
  json_content=$(fetch_json "$json_url")

  # extract package and version data
  # use subshell and capturing to avoid pipefail issues in variable assignment
  local read_data
  read_data=$(echo "$json_content" | jq -r '
    .Releases[0] |
    {Version: .Version, File: (.File[] | select(.Identifier | contains(".deb")))} |
    "\(.Version) \(.File.Sha512CheckSum) \(.File.Url)"
  ')

  local latest_version checksum deb_url
  read -r latest_version checksum deb_url <<< "$read_data"

  if [[ -z "$latest_version" || "$latest_version" == "null" ||
        -z "$checksum"       || "$checksum"       == "null" ||
        -z "$deb_url"        || "$deb_url"        == "null" ]]; then
    log_error "Could not extract data from JSON."
    exit 1
  fi

  local file_name
  file_name="$(basename "$deb_url")"

  log_debug "Most recent online version: $latest_version"
  log_debug "Download URL: $deb_url"

  # idempotency check (version comparison)
  local installed_version
  installed_version=$(dpkg-query -W -f='${Version}' "$package_name" 2>/dev/null || true)

  if [[ -n "$installed_version" ]] && dpkg --compare-versions "$installed_version" ge "$latest_version"; then
    log_info "$package_name is already up to date (Version $installed_version)."
    exit 0
  fi

  if [[ -z "$installed_version" ]]; then
    log_info "$package_name is not installed. Preparing version $latest_version."
  else
    log_info "Update available: $installed_version -> $latest_version"
  fi
  log_debug "Checksum: $checksum"

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
  if [[ -f "$file_name" ]]; then
    log_debug "File $file_name exists. Checking integrity..."
    # --status: suppress output; a hash mismatch here is non-fatal (we just re-download)
    if echo "$checksum  $file_name" | sha512sum --check --status 2>/dev/null; then
      log_info "Local file valid. Skipping download."
      file_already_valid=true
    else
      log_info "Local file hash mismatch. Re-downloading."
      rm -f "$file_name"
    fi
  fi

  # download (with retries)
  if [[ "$file_already_valid" == "false" ]]; then
    log_info "Downloading $file_name..."
    download_file "$file_name" "$deb_url"

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
  [[ "${CLEANUP}" == "true" ]] && {
    log_debug "Cleaning up: Removing $file_name"
    rm -f "$file_name"
  }
  log_info "Process for $package_name complete."
}

# main
main() {
  parse_args "$@"
  check_dependencies "curl" "jq"
  if [[ "$ACTION" == "cli" ]]; then
    check_dependencies "sha256sum"
    update_pass_cli "$PASS_CLI_INSTALL_DIR"
  else
    check_dependencies "sha512sum" "dpkg" "dpkg-query" "sudo"
    update_proton "$PACKAGE_NAME" "$JSON_URL" "$DOWNLOAD_DIR"
  fi
}

main "$@"
