#!/usr/bin/env bash
set -euo pipefail

# Install Miniconda (Python + conda) into ~/miniconda3 and configure it
# for fast, reproducible resolution:
#   - libmamba solver (10-100x faster than the legacy classic solver)
#   - strict channel priority (no silent mixing across channels)
#   - auto_activate_base off (clean shells; .zshrc still sources conda.sh
#     so `conda activate <env>` works on demand)
#
# .zshrc sources ~/miniconda3/etc/profile.d/conda.sh on shell start when
# present, so no `conda init` writeback is needed.

PREFIX="${CONDA_PREFIX_DIR:-$HOME/miniconda3}"
CONDA="$PREFIX/bin/conda"

install_miniconda() {
    case "$(uname -m)" in
        x86_64)  arch="x86_64" ;;
        aarch64) arch="aarch64" ;;
        arm64)   arch="aarch64" ;;
        *) echo "[dots] Unsupported arch: $(uname -m)" >&2; exit 1 ;;
    esac

    url="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-${arch}.sh"
    tmp=$(mktemp --suffix=.sh)
    trap 'rm -f "$tmp"' RETURN

    echo "[dots] Downloading Miniconda installer for $arch..."
    curl -fsSL "$url" -o "$tmp"

    echo "[dots] Installing Miniconda to $PREFIX (silent, no .zshrc modification)..."
    bash "$tmp" -b -p "$PREFIX"
}

if [ -d "$PREFIX" ]; then
    echo "[dots] Miniconda already present at $PREFIX — reconfiguring."
else
    install_miniconda
fi

# Recent conda (24.x+) refuses non-interactive ops against repo.anaconda.com
# channels until their ToS is explicitly accepted. Do it up front.
echo "[dots] Accepting Anaconda channel ToS..."
"$CONDA" tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || true
"$CONDA" tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r    || true

echo "[dots] Updating conda to latest..."
"$CONDA" update -n base -c defaults conda -y

echo "[dots] Installing libmamba solver..."
"$CONDA" install -n base -c conda-forge conda-libmamba-solver -y

echo "[dots] Setting conda config: solver=libmamba, channel_priority=strict, auto_activate_base=false..."
"$CONDA" config --set solver libmamba
"$CONDA" config --set channel_priority strict
"$CONDA" config --set auto_activate_base false

echo "[dots] Miniconda installed and configured. Open a new shell, then 'conda activate <env>' on demand."
