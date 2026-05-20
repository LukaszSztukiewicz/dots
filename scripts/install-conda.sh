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
