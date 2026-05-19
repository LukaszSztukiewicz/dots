#!/usr/bin/env bash
# bw wrapper that injects --session "$BW_SESSION" and --nointeraction on
# every call. Workaround for bw 2026.x (Rust CLI) which has been observed
# to ignore BW_SESSION env in some flows — particularly when called as a
# subprocess from chezmoi during template rendering. In that case bw falls
# back to its interactive master-password prompt, reads garbage from
# whatever stdin happens to be, and fails decrypt on a perfectly valid
# vault.
#
# Configured via `bitwarden.command` in ~/.config/chezmoi/chezmoi.toml
# (set by install.sh). Re-applying chezmoi without BW_SESSION set will
# now fail loudly here instead of mid-prompt.
set -euo pipefail
: "${BW_SESSION:?BW_SESSION not set; cannot call bw}"
exec bw --nointeraction --session "$BW_SESSION" "$@"
