#!/usr/bin/env bash
set -euo pipefail

# Install Neovim from the upstream tarball into /opt and symlink /usr/local/bin/nvim.
# Re-runnable; replaces any existing copy. Needs sudo for the /opt + /usr/local bits.
#
# Why not apt: Ubuntu 24.04 ships Neovim 0.9.5, but LazyVim requires >= 0.11.2.
# Upstream publishes a self-contained tarball per release, so we use that.

TAG="${NVIM_VERSION:-stable}"   # override with NVIM_VERSION=v0.11.5 (etc.) if needed.

# Modern nvim binaries (0.11+) require glibc >= 2.32 (Ubuntu 22.04+). On older
# systems the binary loads but every invocation errors with
# `version 'GLIBC_2.32' not found`. Refuse upfront with a clear message rather
# than half-installing and leaving the user a broken `nvim` in PATH.
if command -v ldd >/dev/null 2>&1; then
    glibc=$(ldd --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
    required=2.32
    if [ -n "$glibc" ] && awk -v g="$glibc" -v r="$required" 'BEGIN{exit !(g+0 < r+0)}'; then
        echo "[dots] nvim: this system has glibc $glibc; nvim binaries need >= $required." >&2
        echo "[dots] Options:" >&2
        echo "[dots]   - Use a newer base image (Ubuntu 22.04+, Debian 12+)." >&2
        echo "[dots]   - Build neovim from source." >&2
        echo "[dots]   - Skip nvim install on this host." >&2
        exit 1
    fi
fi

arch=$(uname -m)
case "$arch" in
    x86_64)  asset="nvim-linux-x86_64.tar.gz"; prefix="/opt/nvim-linux-x86_64" ;;
    aarch64) asset="nvim-linux-arm64.tar.gz";  prefix="/opt/nvim-linux-arm64"  ;;
    *)
        echo "[dots] nvim: unsupported arch '$arch'" >&2
        exit 1
        ;;
esac

# sudo only when not root; minimal root containers may lack sudo entirely.
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    if ! command -v sudo >/dev/null 2>&1; then
        echo "[dots] ERROR: install-nvim.sh needs root for /opt and /usr/local/bin, but sudo is unavailable." >&2
        exit 1
    fi
    SUDO=sudo
fi

# Warn if an existing nvim shadows what we're about to install (e.g. snap, apt).
existing=$(command -v nvim 2>/dev/null || true)
if [ -n "$existing" ] && [ "$existing" != "/usr/local/bin/nvim" ]; then
    echo "[dots] note: an existing nvim is at $existing — /usr/local/bin/nvim will take precedence after install."
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

url="https://github.com/neovim/neovim/releases/download/${TAG}/${asset}"
echo "[dots] Downloading nvim ${TAG} ($asset)"
curl -fsSL "$url" -o "$TMP/$asset"

$SUDO rm -rf "$prefix"
$SUDO mkdir -p "$prefix"
$SUDO tar -xzf "$TMP/$asset" -C "$prefix" --strip-components=1

$SUDO ln -sf "$prefix/bin/nvim" /usr/local/bin/nvim

echo "[dots] nvim installed: $(/usr/local/bin/nvim --version | head -1)"
echo "[dots] On first launch, LazyVim will bootstrap lazy.nvim and install plugins."
