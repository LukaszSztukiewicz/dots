#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib/colors.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/colors.sh"

# Install dua-cli (interactive disk-usage analyzer) as a static binary
# under ~/.local/bin. Re-runnable; replaces any existing copy.
#
# Why a script instead of apt: dua-cli only entered Ubuntu apt in 24.10.
# This keeps 24.04 hosts working without forcing a Rust toolchain install.

DEST="$HOME/.local/bin"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

arch=$(uname -m)
case "$arch" in
    x86_64)  target="x86_64-unknown-linux-musl" ;;
    aarch64) target="aarch64-unknown-linux-musl" ;;
    *)
        c_err "dua-cli: unsupported arch '$arch'"
        exit 1
        ;;
esac

c_step "Resolving latest dua-cli release..."
# Buffer the API response first; piping curl into `grep -m1` closes the pipe
# early and trips curl error 23 (SIGPIPE) under set -o pipefail.
api_json=$(curl -fsSL https://api.github.com/repos/Byron/dua-cli/releases/latest)
tag=$(printf '%s\n' "$api_json" | grep '"tag_name"' | head -1 \
    | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')

if [ -z "$tag" ]; then
    c_err "dua-cli: could not resolve latest release tag"
    exit 1
fi

asset="dua-${tag}-${target}.tar.gz"
url="https://github.com/Byron/dua-cli/releases/download/${tag}/${asset}"

c_info "Downloading $asset"
curl -fsSL "$url" -o "$TMP/$asset"

tar -xzf "$TMP/$asset" -C "$TMP"

mkdir -p "$DEST"
install -m 0755 "$TMP/dua-${tag}-${target}/dua" "$DEST/dua"

c_ok "dua installed at $DEST/dua ($("$DEST/dua" --version))"
