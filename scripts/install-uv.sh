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

# Install uv (fast Python package + project manager from Astral). Re-runnable.
# After install, open a new shell — .zshrc sources ~/.local/bin/env which uv drops there.

c_step "Installing uv..."
curl -fsSL https://astral.sh/uv/install.sh | sh

c_ok "uv installed. Open a new shell or run: . \"\$HOME/.local/bin/env\""
