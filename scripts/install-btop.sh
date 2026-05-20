#!/usr/bin/env bash
set -euo pipefail

# Source shared color lib (repo-local) or fall back to inline shims so
# this script also works via `curl | bash` without the repo cloned.
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
