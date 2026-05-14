#!/bin/bash

set -euo pipefail

# Configuration, defaults
SCRIPT_NAME="$(basename "$0")"
REPO_OWNER="czandee"
REPO_NAME="proton-updater"
TARGET_VERSION="latest"
ACTION="install"
TMP_DIR=""

function usage {
  cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS] [VERSION]

Options:
  -u, --uninstall   Uninstall the app
  -h, --help        Show this help page

Version:
  The release/version tag to install (default: latest)

Examples:
  $SCRIPT_NAME                   # install latest version
  $SCRIPT_NAME v1.2.1            # install version v1.2.1
  $SCRIPT_NAME --uninstall       # uninstall the current version

EOF
}

function cleanup {
  [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

# Check OS and distro family
if [[ "$OSTYPE" != "linux-gnu"* ]]; then
  echo "Error: This script is intended for Debian-based Linux systems only."
  exit 1
fi
if ! command -v dpkg &>/dev/null; then
  echo "Error: dpkg not found. This script requires a Debian-based Linux system."
  exit 1
fi

# Parse command line (not very robust but simple)
while [[ "$#" -gt 0 ]]; do
  case $1 in
    -h|--help) usage; exit 0;;
    -u|--uninstall) ACTION="uninstall" ;;
    -*) echo "Error: Unknown option '$1'."; usage; exit 1;;
    *) TARGET_VERSION="$1";;
  esac
  shift
done

# Uninstall doesn't need a release — remove known binaries directly
if [ "$ACTION" == "uninstall" ]; then
  echo "Uninstalling..."
  rm -f "${HOME}/.local/bin/update-proton"
  echo "Uninstall complete!"
  exit 0
fi

# Check dependencies
for cmd in curl tar make jq; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "Error: $cmd is required. Please install it using your package manager."
    exit 1
  fi
done

# Get release metadata from github
echo "Fetching metadata for version: $TARGET_VERSION..."
if [ "$TARGET_VERSION" = "latest" ]; then
  API_URL="https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/latest"
else
  # GitHub tags are usually prefixed with 'v', but we handle both cases
  API_URL="https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/tags/$TARGET_VERSION"
fi

# Get release data, raise error on any http code error returned to curl
RELEASE_DATA=$(curl -sf -m 30 "$API_URL") || {
  echo "Error: Could not fetch release '$TARGET_VERSION'. Check GitHub version tags or your network."
  exit 1
}

read -r TARBALL_URL VERSION_TAG < <(echo "$RELEASE_DATA" | jq -r '[.tarball_url, .tag_name] | @tsv')

# Validate the tarball_url and version_tag fields
error_msg="Error: Could not determine"
[[ "$TARBALL_URL" == "null" || -z "$TARBALL_URL" ]] && { echo "$error_msg tarball URL."; exit 1; }
[[ "$VERSION_TAG" == "null" || -z "$VERSION_TAG" ]] && { echo "$error_msg version tag."; exit 1; }

echo "Preparing to $ACTION $VERSION_TAG..."

# Download and unpack tarball into a temporary directory
TMP_DIR=$(mktemp -d)
echo "Downloading ..."
curl -sfL -m 120 "$TARBALL_URL" | tar xz -C "$TMP_DIR" --strip-components=1

# Execute the makefile (target install)
(
  cd "$TMP_DIR" || exit 1
  echo "Installing..."
  make install
) || exit 1

echo "${ACTION^} of $VERSION_TAG complete!"
