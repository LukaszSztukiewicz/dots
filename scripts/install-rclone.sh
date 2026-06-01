#!/usr/bin/env bash
set -euo pipefail

c_step() { printf '==> %s\n' "$*"; }
c_info() { printf '[dots] %s\n' "$*"; }
c_ok()   { printf '[ ok ] %s\n' "$*"; }
c_warn() { printf '[warn] %s\n' "$*" >&2; }
c_err()  { printf '[ERR ] %s\n' "$*" >&2; }
error()  { c_err "$*"; exit 1; }
# shellcheck source=lib/colors.sh
_lib="$(dirname "${BASH_SOURCE[0]:-$0}")/lib/colors.sh"
{ [ -r "$_lib" ] && . "$_lib"; } || {
    _tmp=$(mktemp)
    curl -fsSL "${DOTS_RAW:-https://raw.githubusercontent.com/LukaszSztukiewicz/dots/main}/scripts/lib/colors.sh" \
        -o "$_tmp" 2>/dev/null && . "$_tmp"
    rm -f "$_tmp"
}
unset _lib _tmp

DEST="$HOME/.local/bin"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

arch=$(uname -m)
case "$arch" in
    x86_64)  target="linux-amd64" ;;
    aarch64) target="linux-arm64" ;;
    *)
        c_err "rclone: unsupported arch '$arch'"
        exit 1
        ;;
esac

tag="v1.74.2"
asset="rclone-${tag}-${target}.zip"
url="https://github.com/rclone/rclone/releases/download/${tag}/${asset}"

c_step "Installing rclone ${tag}..."
c_info "Downloading $asset"
curl -fsSL "$url" -o "$TMP/$asset"

if command -v unzip >/dev/null 2>&1; then
    unzip -q "$TMP/$asset" -d "$TMP"
elif command -v python3 >/dev/null 2>&1; then
    python3 -m zipfile -e "$TMP/$asset" "$TMP"
else
    c_err "Neither 'unzip' nor 'python3' is available to extract the archive."
    exit 1
fi

mkdir -p "$DEST"
install -m 0755 "$TMP/rclone-${tag}-${target}/rclone" "$DEST/rclone"

c_ok "rclone installed at $DEST/rclone ($("$DEST/rclone" --version | head -n1))"
