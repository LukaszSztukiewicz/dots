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

# Install SDKMAN (Java, Kotlin, Gradle, Maven, etc.). Re-running is safe.
# After install, open a new shell and use `sdk install java <version>` etc.

if [ -d "$HOME/.sdkman" ]; then
    c_info "SDKMAN already installed at $HOME/.sdkman — skipping."
    exit 0
fi

c_step "Installing SDKMAN..."
curl -fsSL https://get.sdkman.io | bash

c_ok "SDKMAN installed. Open a new shell to start using it."
