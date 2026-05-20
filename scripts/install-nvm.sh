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

# Install Node Version Manager. Re-running is safe (upstream script is idempotent).
# After install, open a new shell or `source ~/.zshrc` to pick up nvm.

NVM_VERSION="${NVM_VERSION:-v0.39.7}"

c_step "Installing nvm ${NVM_VERSION}..."
curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash

c_ok "nvm installed. Open a new shell and run 'nvm install --lts' to get Node."
