#!/usr/bin/env bash
set -euo pipefail

_bw_ensure_session() {
    local status
    status=$(bw status 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])" 2>/dev/null || echo "error")

    case "$status" in
        unlocked)
            ;;
        locked)
            echo "[dots] Bitwarden vault is locked. Unlocking..."
            BW_SESSION=$(bw unlock --raw)
            export BW_SESSION
            ;;
        unauthenticated)
            echo "[dots] Not logged in to Bitwarden. Logging in..."
            bw login
            echo "[dots] Login complete. Unlocking vault..."
            BW_SESSION=$(bw unlock --raw)
            export BW_SESSION
            ;;
        *)
            echo "[dots] ERROR: could not determine Bitwarden status (got: '$status')." >&2
            echo "[dots] Is the Bitwarden CLI installed? Run: which bw" >&2
            exit 1
            ;;
    esac
}

_bw_ensure_session
exec chezmoi apply "$@"
