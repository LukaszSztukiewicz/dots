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

_bw_session_valid() {
    # See install.sh for why we use `list folders` instead of `unlock --check`.
    [ -n "${BW_SESSION:-}" ] && bw list folders --raw >/dev/null 2>&1
}

_bw_unlock_interactive() {
    local pw err_file unlock_out unlock_rc

    if [ -n "${BW_PASSWORD:-}" ]; then
        pw="$BW_PASSWORD"
    elif _have_tty; then
        printf '[dots] Bitwarden master password: ' >/dev/tty
        IFS= read -rs pw </dev/tty
        printf '\n' >/dev/tty
        [ -n "$pw" ] || error "Empty master password."
    else
        error "Bitwarden unlock required, no TTY and BW_PASSWORD unset."
    fi

    err_file=$(mktemp)
    if unlock_out=$(BW_PASSWORD="$pw" bw unlock --passwordenv BW_PASSWORD --raw 2>"$err_file"); then
        unlock_rc=0
    else
        unlock_rc=$?
    fi
    unset pw

    if [ "$unlock_rc" -ne 0 ]; then
        local err_msg
        err_msg=$(cat "$err_file")
        rm -f "$err_file"
        error "bw unlock failed (exit $unlock_rc): ${err_msg:-<no stderr output>}"
    fi
    rm -f "$err_file"
    [ -n "$unlock_out" ] || error "bw unlock returned exit 0 but no session token."
    export BW_SESSION="$unlock_out"
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
