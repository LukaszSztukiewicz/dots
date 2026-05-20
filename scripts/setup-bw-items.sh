#!/usr/bin/env bash
set -euo pipefail

# Bootstrap the Bitwarden items this dotfiles repo expects. Idempotent — re-runs
# are safe; existing items are left alone.
#
# Items created:
#   dots-git-secrets (Secure Note)
#     field credential_helper = "store"   (consumed by dot_gitconfig.tmpl)
#
# Run manually after `bw login` + `bw unlock` (or with a valid BW_SESSION set).
# No jq required — we construct the item JSON inline so this is safe to call
# from install.sh before chezmoi has installed packages.

# shellcheck source=lib/colors.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/colors.sh"

info()  { c_info "$*"; }
error() { c_err "$*"; exit 1; }

command -v bw >/dev/null 2>&1 || error "bw (Bitwarden CLI) not found in PATH."
[ -n "${BW_SESSION:-}" ] || error "BW_SESSION not set. Run install.sh or \`bw unlock\` first."

# bw helper: always pass the session explicitly and disable interactive
# prompts. bw 2026.x (Rust CLI) was observed to ignore BW_SESSION env in
# some flows and fall back to a stdin password prompt — under `curl|bash`
# that reads garbage from the script pipe and "successfully fails" decrypt.
# --nointeraction makes it error out instead.
_bw() { bw --nointeraction --session "$BW_SESSION" "$@"; }

# Session validity probe.
bw_probe_err=$(_bw list folders 2>&1 >/dev/null) || \
    error "Bitwarden vault not accessible. bw said: ${bw_probe_err:-<no stderr>}"

# --- dots-git-secrets ---
if _bw get item "dots-git-secrets" >/dev/null 2>&1; then
    info "dots-git-secrets already exists. Skipping."
else
    info "Creating dots-git-secrets in Bitwarden..."
    # Hand-crafted item JSON. type=2 = Secure Note, secureNote.type=0 = Generic.
    # Field type=0 = Text. This is the same shape `bw get template item` would
    # produce, just without the jq round-trip.
    item_json='{"organizationId":null,"collectionIds":null,"folderId":null,"type":2,"name":"dots-git-secrets","notes":null,"favorite":false,"fields":[{"name":"credential_helper","value":"store","type":0,"linkedId":null}],"secureNote":{"type":0}}'
    # `bw encode` is local base64 with no vault access, so it doesn't need the
    # session. `bw create item` does.
    printf '%s' "$item_json" | bw encode | _bw create item >/dev/null
    info "dots-git-secrets created."
fi
