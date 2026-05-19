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

info()  { echo "[dots] $*"; }
error() { echo "[dots] ERROR: $*" >&2; exit 1; }

command -v bw >/dev/null 2>&1 || error "bw (Bitwarden CLI) not found in PATH."
command -v jq >/dev/null 2>&1 || error "jq not found in PATH."

# Make sure the vault is unlocked before we touch it. `bw status` returns
# 'unlocked' only when a valid BW_SESSION is in scope.
status=$(bw status 2>/dev/null | jq -r '.status' 2>/dev/null || echo "error")
case "$status" in
    unlocked) ;;
    locked|unauthenticated)
        error "Bitwarden vault is $status. Run \`bw unlock\` (or set BW_SESSION) and retry."
        ;;
    *)
        error "Could not determine Bitwarden status (got: '$status')."
        ;;
esac

# --- dots-git-secrets ---
if bw get item "dots-git-secrets" >/dev/null 2>&1; then
    info "dots-git-secrets already exists. Skipping."
else
    info "Creating dots-git-secrets in Bitwarden..."
    bw get template item \
        | jq '.name="dots-git-secrets"
              | .type=2
              | .secureNote={"type":0}
              | .fields=[{"name":"credential_helper","value":"store","type":0,"linkedId":null}]' \
        | bw encode \
        | bw create item >/dev/null
    info "dots-git-secrets created."
fi
