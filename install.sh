#!/bin/bash

# Configuration, defaults
REPO_OWNER="czandee"
REPO_NAME="proton-updater"
TARGET_VERSION="latest"
ACTION="install"

function usage {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] [VERSION]

Options:
  -u, --uninstall   Uninstall the app
  -h, --help        Show this help page

Version:
  The release/version tag to install (default: latest)

Examples:
  $0                   # install latest version
  $0 v1.0.0            # install version v1.0.0
  $0 --uninstall       # uninstall the current version

EOF
}

function cleanup {
  [[ -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

# Check OS
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
  echo "Error: This script is intended for Linux/macOS."
  exit 1
fi

# Parse command line (not very robust but simple)
while [[ "$#" -gt 0 ]]; do
  case $1 in
    -h|--help) usage; exit 0;;
    -u|--uninstall) ACTION="uninstall" ;;
    *) TARGET_VERSION="$1";;
  esac
  shift
done

# Check dependencies
for cmd in curl tar make; do
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

RELEASE_DATA=$(curl -s "$API_URL")

# Check if the release actually exists
if echo "$RELEASE_DATA" | grep -q "Not Found"; then
  echo "Error: Version '$TARGET_VERSION' not found in the GitHub releases."
  exit 1
fi

TARBALL_URL=$(echo "$RELEASE_DATA" | grep "tarball_url" | cut -d '"' -f 4)
VERSION_TAG=$(echo "$RELEASE_DATA" | grep "tag_name" | cut -d '"' -f 4)

echo "Preparing to $ACTION $VERSION_TAG..."

# Download and unpack tarball into a temporary directory
TMP_DIR=$(mktemp -d)
echo "Downloading ..."
curl -sL "$TARBALL_URL" | tar xz -C "$TMP_DIR" --strip-components=1

# Execute the makefile (target install)
(
  cd "$TMP_DIR" || exit 1
  if [ "$ACTION" == "uninstall" ]; then
    echo "Uninstalling..."
    make uninstall
  else
    echo "Installing..."
    make install
  fi
) || exit 1

echo "${ACTION^} of $VERSION_TAG complete!"
