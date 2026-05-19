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

info()  { echo "[dots] $*"; }
error() { echo "[dots] ERROR: $*" >&2; exit 1; }

command -v bw >/dev/null 2>&1 || error "bw (Bitwarden CLI) not found in PATH."

# `bw status` is unreliable as a session-validity check: when the vault was
# unlocked with `--raw` (which is what install.sh does) the on-disk state
# stays "locked" even though BW_SESSION in env is a working session. Test
# the session end-to-end by hitting an operation that requires decryption.
if [ -z "${BW_SESSION:-}" ] || ! bw list folders --raw >/dev/null 2>&1; then
    error "Bitwarden vault is not accessible. Set BW_SESSION (e.g. \`export BW_SESSION=\$(bw unlock --raw)\`) and retry."
fi

# --- dots-git-secrets ---
if bw get item "dots-git-secrets" >/dev/null 2>&1; then
    info "dots-git-secrets already exists. Skipping."
else
    info "Creating dots-git-secrets in Bitwarden..."
    # Hand-crafted item JSON. type=2 = Secure Note, secureNote.type=0 = Generic.
    # Field type=0 = Text. This is the same shape `bw get template item` would
    # produce, just without the jq round-trip.
    item_json='{"organizationId":null,"collectionIds":null,"folderId":null,"type":2,"name":"dots-git-secrets","notes":null,"favorite":false,"fields":[{"name":"credential_helper","value":"store","type":0,"linkedId":null}],"secureNote":{"type":0}}'
    printf '%s' "$item_json" | bw encode | bw create item >/dev/null
    info "dots-git-secrets created."
fi
