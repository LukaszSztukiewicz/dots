#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib/colors.sh
. "$(dirname "${BASH_SOURCE[0]:-/dev/null}")/lib/colors.sh" 2>/dev/null || {
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ -z "${DOTS_NO_COLOR:-}" ]; then
        _r=$'\033[0m'; _C=$'\033[36m'; _B=$'\033[34m'; _G=$'\033[32m'; _Y=$'\033[33m'; _R=$'\033[31m'
    else _r=; _C=; _B=; _G=; _Y=; _R=; fi
    c_step(){ printf '%s==>%s %s\n'    "$_C" "$_r" "$*"; }
    c_info(){ printf '%s[dots]%s %s\n' "$_B" "$_r" "$*"; }
    c_ok()  { printf '%s[ ok ]%s %s\n' "$_G" "$_r" "$*"; }
    c_warn(){ printf '%s[warn]%s %s\n' "$_Y" "$_r" "$*" >&2; }
    c_err() { printf '%s[ERR ]%s %s\n' "$_R" "$_r" "$*" >&2; }
}

# Install a static tmux binary into ~/.local/bin/tmux so OSC52 clipboard
# passthrough works on systems where the apt-shipped tmux is too old.
#
# Override the version via TMUX_VERSION env var. If the specified version
# fails, you can run: TMUX_VERSION="latest" ./install-tmux.sh

TMUX_VERSION="${TMUX_VERSION:-3.5a}"
DEST_BIN="$HOME/.local/bin/tmux"

arch=$(uname -m)
case "$arch" in
    x86_64) ;;
    *)
        c_err "install-tmux.sh: unsupported arch '$arch' (only x86_64 prebuilds available)."
        c_err "Build tmux from source or use the apt package on this host."
        exit 1
        ;;
esac

mkdir -p "$HOME/.local/bin"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# 1. Dynamically resolve the URL using the GitHub API
if [ "$TMUX_VERSION" = "latest" ]; then
    API_URL="https://api.github.com/repos/nelsonenzo/tmux-appimage/releases/latest"
    TAG="latest"
else
    TAG="${TMUX_VERSION}"
    API_URL="https://api.github.com/repos/nelsonenzo/tmux-appimage/releases/tags/${TAG}"
fi

c_step "Resolving download URL for ${TAG}..."

# Fetch API response and capture the HTTP status code
HTTP_CODE=$(curl -sL -w "%{http_code}" "$API_URL" -o "$TMP/api.json")

if [ "$HTTP_CODE" != "200" ]; then
    c_err "GitHub API returned HTTP ${HTTP_CODE} for tag '${TAG}'."
    c_err "Version ${TMUX_VERSION} might not be released yet, or the tag name changed."
    c_info "Try running with the latest release: TMUX_VERSION=latest $0"
    exit 1
fi

# Extract the download URL avoiding jq dependency (useful for bootstrapping)
url=$(grep -o '"browser_download_url": *"[^"]*"' "$TMP/api.json" | grep -i 'appimage' | cut -d '"' -f 4 | head -n 1)

if [ -z "$url" ]; then
    c_err "Found the release, but could not find an AppImage asset inside it."
    exit 1
fi

asset=$(basename "$url")

# 2. Download and Extract
c_step "Downloading $asset..."
curl -fsSL "$url" -o "$TMP/$asset" || {
    c_err "Download failed."
    exit 1
}

chmod +x "$TMP/$asset"

c_info "Extracting appimage..."
(cd "$TMP" && "./$asset" --appimage-extract >/dev/null)

extracted="$TMP/squashfs-root/usr/bin/tmux"
if [ ! -x "$extracted" ]; then
    # Some appimage layouts place the binary at a different path. Probe.
    extracted=$(find "$TMP/squashfs-root" -type f -name tmux -executable | head -1)
fi
[ -x "$extracted" ] || { c_err "Could not locate tmux binary inside the appimage."; exit 1; }

install -m 0755 "$extracted" "$DEST_BIN"

c_ok "tmux installed at $DEST_BIN ($("$DEST_BIN" -V))"
c_info "Open a new shell so PATH picks up ~/.local/bin/tmux ahead of the system tmux."