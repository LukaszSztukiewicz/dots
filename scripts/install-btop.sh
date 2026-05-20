#!/usr/bin/env bash
set -euo pipefail

c_step() { printf '==> %s
' "$*"; }
c_info() { printf '[dots] %s
' "$*"; }
c_ok()   { printf '[ ok ] %s
' "$*"; }
c_warn() { printf '[warn] %s
' "$*" >&2; }
c_err()  { printf '[ERR ] %s
' "$*" >&2; }
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

# Install btop (resource monitor) as a static binary under ~/.local/bin.
# Re-runnable; replaces any existing copy. Installs bundled themes into
# ~/.config/btop/themes/ alongside the chezmoi-managed btop.conf.
#
# Why a script instead of apt: btop entered Ubuntu apt in 22.04. On older
# Ubuntu, Debian stable, and stripped-down containers it isn't packaged.
# Upstream ships a static musl binary that works everywhere.

DEST="$HOME/.local/bin"
THEMES_DIR="$HOME/.config/btop/themes"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

arch=$(uname -m)
case "$arch" in
    x86_64)  target="x86_64-unknown-linux-musl" ;;
    aarch64) target="aarch64-unknown-linux-musl" ;;
    *)
        c_err "btop: unsupported arch '$arch'"
        exit 1
        ;;
esac

c_step "Resolving latest btop release..."
api_json=$(curl -fsSL https://api.github.com/repos/aristocratos/btop/releases/latest)
tag=$(printf '%s\n' "$api_json" | grep '"tag_name"' | head -1 \
    | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')

if [ -z "$tag" ]; then
    c_err "btop: could not resolve latest release tag"
    exit 1
fi

asset="btop-${target}.tar.gz"
url="https://github.com/aristocratos/btop/releases/download/${tag}/${asset}"

c_info "Downloading $asset (${tag})"
curl -fsSL "$url" -o "$TMP/$asset"

tar -xzf "$TMP/$asset" -C "$TMP"

mkdir -p "$DEST" "$THEMES_DIR"
install -m 0755 "$TMP/btop/bin/btop" "$DEST/btop"
cp -a "$TMP/btop/themes/." "$THEMES_DIR/"

c_ok "btop installed at $DEST/btop ($("$DEST/btop" --version 2>&1 | head -1))"
c_ok "Themes copied to $THEMES_DIR"
