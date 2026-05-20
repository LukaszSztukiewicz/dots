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

# Install Node Version Manager. Re-running is safe (upstream script is idempotent).
# After install, open a new shell or `source ~/.zshrc` to pick up nvm.

NVM_VERSION="${NVM_VERSION:-v0.39.7}"

c_step "Installing nvm ${NVM_VERSION}..."
curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash

c_ok "nvm installed. Open a new shell and run 'nvm install --lts' to get Node."
