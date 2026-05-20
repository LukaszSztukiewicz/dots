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

# Install juliaup (Julia version manager). Re-running re-applies the upstream
# installer, which is idempotent.
# After install, open a new shell and run `julia` (juliaup auto-installs the
# default Julia channel on first call) or `juliaup add release`.

c_step "Installing juliaup..."
# -y skips the interactive shell-config writeback; .zshrc already prepends
# ~/.juliaup/bin guarded by an existence check.
curl -fsSL https://install.julialang.org | sh -s -- --yes

c_ok "juliaup installed. Open a new shell to use it."
