#!/usr/bin/env bash
set -euo pipefail

# Keep this Bitwarden flow in sync with install.sh::_bw_ensure_session.
# Reason for the song-and-dance: when BW_SESSION in env is stale, `bw status`
# still returns "unlocked", but downstream `bw get item` calls fail and
# silently fall back to a tty password prompt that mis-decodes input under
# /dev/tty redirection. `bw unlock --check` is the only reliable test.

info()  { echo "[dots] $*"; }
error() { echo "[dots] ERROR: $*" >&2; exit 1; }

_have_tty() { (exec </dev/tty) 2>/dev/null; }

_bw_session_valid() { [ -n "${BW_SESSION:-}" ] && bw unlock --check >/dev/null 2>&1; }

_bw_unlock_interactive() {
    if [ -n "${BW_PASSWORD:-}" ]; then
        BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw)
    elif _have_tty; then
        local bw_pw=""
        printf '[dots] Bitwarden master password: ' >/dev/tty
        IFS= read -rs bw_pw </dev/tty
        printf '\n' >/dev/tty
        [ -n "$bw_pw" ] || error "Empty master password."
        BW_SESSION=$(BW_PASSWORD="$bw_pw" bw unlock --passwordenv BW_PASSWORD --raw)
        unset bw_pw
    else
        error "Bitwarden unlock required, no TTY and BW_PASSWORD unset."
    fi
    export BW_SESSION
}

_bw_ensure_session() {
    if _bw_session_valid; then
        return
    fi
    unset BW_SESSION

    local status
    status=$(bw status 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])" 2>/dev/null || echo "error")

    case "$status" in
        unlocked|locked)
            [ "$status" = "unlocked" ] && bw lock >/dev/null 2>&1 || true
            info "Unlocking Bitwarden vault..."
            ;;
        unauthenticated)
            info "Not logged in to Bitwarden. Logging in..."
            bw login
            info "Login complete. Unlocking vault..."
            ;;
        *)
            error "Could not determine Bitwarden status (got: '$status'). Is bw installed?"
            ;;
    esac

    _bw_unlock_interactive
}

_bw_ensure_session
exec chezmoi apply "$@"
