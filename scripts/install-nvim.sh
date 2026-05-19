#!/usr/bin/env bash
set -euo pipefail

# Install Neovim from the upstream tarball into /opt and symlink /usr/local/bin/nvim.
# Re-runnable; replaces any existing copy. Needs sudo for the /opt + /usr/local bits.
#
# Why not apt: Ubuntu 24.04 ships Neovim 0.9.5, but LazyVim requires >= 0.11.2.
# Upstream publishes a self-contained tarball per release, so we use that.

TAG="${NVIM_VERSION:-stable}"   # override with NVIM_VERSION=v0.11.5 (etc.) if needed.

arch=$(uname -m)
case "$arch" in
    x86_64)  asset="nvim-linux-x86_64.tar.gz"; prefix="/opt/nvim-linux-x86_64" ;;
    aarch64) asset="nvim-linux-arm64.tar.gz";  prefix="/opt/nvim-linux-arm64"  ;;
    *)
        echo "[dots] nvim: unsupported arch '$arch'" >&2
        exit 1
        ;;
esac

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

url="https://github.com/neovim/neovim/releases/download/${TAG}/${asset}"
echo "[dots] Downloading nvim ${TAG} ($asset)"
curl -fsSL "$url" -o "$TMP/$asset"

sudo rm -rf "$prefix"
sudo mkdir -p "$prefix"
sudo tar -xzf "$TMP/$asset" -C "$prefix" --strip-components=1

sudo ln -sf "$prefix/bin/nvim" /usr/local/bin/nvim

echo "[dots] nvim installed: $(/usr/local/bin/nvim --version | head -1)"
echo "[dots] On first launch, LazyVim will bootstrap lazy.nvim and install plugins."
