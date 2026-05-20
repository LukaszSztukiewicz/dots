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
        *) c_err "Unsupported arch: $(uname -m)"; exit 1 ;;
    esac

    url="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-${arch}.sh"
    tmp=$(mktemp --suffix=.sh)
    trap 'rm -f "$tmp"' RETURN

    c_info "Downloading Miniconda installer for $arch..."
    curl -fsSL "$url" -o "$tmp"

    c_info "Installing Miniconda to $PREFIX (silent, no .zshrc modification)..."
    bash "$tmp" -b -p "$PREFIX"
}

if [ -d "$PREFIX" ]; then
    c_info "Miniconda already present at $PREFIX — reconfiguring."
else
    install_miniconda
fi

# Recent conda (24.x+) refuses non-interactive ops against repo.anaconda.com
# channels until their ToS is explicitly accepted. Do it up front.
c_step "Accepting Anaconda channel ToS..."
"$CONDA" tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || true
"$CONDA" tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r    || true

c_step "Updating conda to latest..."
"$CONDA" update -n base -c defaults conda -y

c_step "Installing libmamba solver..."
"$CONDA" install -n base -c conda-forge conda-libmamba-solver -y

c_step "Setting conda config: solver=libmamba, channel_priority=strict, auto_activate_base=false..."
"$CONDA" config --set solver libmamba
"$CONDA" config --set channel_priority strict
"$CONDA" config --set auto_activate_base false

c_ok "Miniconda installed and configured. Open a new shell, then 'conda activate <env>' on demand."
