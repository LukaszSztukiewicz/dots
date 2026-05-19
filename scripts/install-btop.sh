#!/usr/bin/env bash
set -euo pipefail

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
        echo "[dots] btop: unsupported arch '$arch'" >&2
        exit 1
        ;;
esac

echo "[dots] Resolving latest btop release..."
api_json=$(curl -fsSL https://api.github.com/repos/aristocratos/btop/releases/latest)
tag=$(printf '%s\n' "$api_json" | grep '"tag_name"' | head -1 \
    | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')

if [ -z "$tag" ]; then
    echo "[dots] btop: could not resolve latest release tag" >&2
    exit 1
fi

asset="btop-${target}.tar.gz"
url="https://github.com/aristocratos/btop/releases/download/${tag}/${asset}"

echo "[dots] Downloading $asset (${tag})"
curl -fsSL "$url" -o "$TMP/$asset"

tar -xzf "$TMP/$asset" -C "$TMP"

mkdir -p "$DEST" "$THEMES_DIR"
install -m 0755 "$TMP/btop/bin/btop" "$DEST/btop"
cp -a "$TMP/btop/themes/." "$THEMES_DIR/"

echo "[dots] btop installed at $DEST/btop ($("$DEST/btop" --version 2>&1 | head -1))"
echo "[dots] Themes copied to $THEMES_DIR"
