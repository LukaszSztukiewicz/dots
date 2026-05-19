#!/usr/bin/env bash
set -euo pipefail

# Install Miniconda (Python + conda) into ~/miniconda3.
# .zshrc sources ~/miniconda3/etc/profile.d/conda.sh on shell start when present,
# so no `conda init` is needed.

PREFIX="${CONDA_PREFIX_DIR:-$HOME/miniconda3}"

if [ -d "$PREFIX" ]; then
    echo "[dots] Miniconda already present at $PREFIX — skipping."
    exit 0
fi

case "$(uname -m)" in
    x86_64)  arch="x86_64" ;;
    aarch64) arch="aarch64" ;;
    arm64)   arch="aarch64" ;;
    *) echo "[dots] Unsupported arch: $(uname -m)" >&2; exit 1 ;;
esac

url="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-${arch}.sh"
tmp=$(mktemp --suffix=.sh)
trap 'rm -f "$tmp"' EXIT

echo "[dots] Downloading Miniconda installer for $arch..."
curl -fsSL "$url" -o "$tmp"

echo "[dots] Installing Miniconda to $PREFIX (silent, no .zshrc modification)..."
bash "$tmp" -b -p "$PREFIX"

echo "[dots] Miniconda installed. Open a new shell to activate."
