#!/usr/bin/env bash
set -euo pipefail

# pick.sh — interactive tool selector for dots.
#
# Presents a whiptail checklist to select individual tools or kick off a full
# dots install (bootstrap.sh). Each selected tool script is
# fetched from raw GitHub and piped to bash — no repo clone required.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/LukaszSztukiewicz/dots/main/scripts/pick.sh | bash

DOTS_RAW="${DOTS_RAW:-https://raw.githubusercontent.com/LukaszSztukiewicz/dots/main}"

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

command_exists() { command -v "$1" &>/dev/null; }

_apt() {
  if [ "$(id -u)" -eq 0 ]; then
    apt-get "$@"
  elif command_exists sudo; then
    sudo apt-get "$@"
  else
    return 1
  fi
}

# Ensure whiptail is available; fall back to numbered-list on non-apt systems.
_ensure_whiptail() {
  command_exists whiptail && return 0
  if command_exists apt-get; then
    c_info "Installing whiptail..."
    export DEBIAN_FRONTEND=noninteractive
    _apt update -qq
    _apt install -y whiptail
  else
    return 1
  fi
}

# ── Tool registry ─────────────────────────────────────────────────────────────
# Order determines install sequence. Format: "key|label|description"
TOOLS=(
  "full-dots|Full dots install|chezmoi + dotfiles (runs bootstrap.sh)"
  "tmux|tmux|Static binary >= 3.5a with OSC52 clipboard support"
  "nvim|Neovim|Latest AppImage (replaces apt nvim)"
  "fzf|fzf|Fuzzy finder with keybindings + completion"
  "nvm|nvm|Node Version Manager"
  "uv|uv|Fast Python package/project manager"
  "conda|conda|Miniconda (Python distribution)"
  "sdkman|SDKMAN|Java/JVM version manager"
  "juliaup|juliaup|Julia version manager"
  "dua|dua|Disk Usage Analyzer"
  "btop|btop|Resource monitor"
)

# ── Selection UI ──────────────────────────────────────────────────────────────
_whiptail_select() {
  local args=()
  local key label desc
  for entry in "${TOOLS[@]}"; do
    IFS='|' read -r key label desc <<< "$entry"
    args+=("$key" "$desc" "OFF")
  done

  local height=$(( ${#TOOLS[@]} + 8 ))
  whiptail \
    --title "dots — tool installer" \
    --checklist "Select what to install (SPACE to toggle, ENTER to confirm):" \
    "$height" 72 "${#TOOLS[@]}" \
    "${args[@]}" \
    3>&1 1>&2 2>&3
}

_numbered_select() {
  printf '\nSelect tools to install (space-separated numbers, or "all"):\n\n'
  local i=1
  local key label desc
  for entry in "${TOOLS[@]}"; do
    IFS='|' read -r key label desc <<< "$entry"
    printf '  %2d) %-12s %s\n' "$i" "$label" "$desc"
    (( i++ ))
  done
  printf '\nYour choice: '
  local input
  read -r input </dev/tty

  local selected=()
  if [ "$input" = "all" ]; then
    for entry in "${TOOLS[@]}"; do
      IFS='|' read -r key _ _ <<< "$entry"
      selected+=("$key")
    done
  else
    for token in $input; do
      local idx=$(( token - 1 ))
      if (( idx >= 0 && idx < ${#TOOLS[@]} )); then
        IFS='|' read -r key _ _ <<< "${TOOLS[$idx]}"
        selected+=("$key")
      fi
    done
  fi
  printf '%s\n' "${selected[@]}"
}

# ── Run a remote script ───────────────────────────────────────────────────────
_run_remote() {
  local name="$1" url="$2"
  c_step "Installing $name..."
  if bash <(curl -fsSL "$url"); then
    c_ok "$name installed."
    return 0
  else
    c_err "$name install failed (see above)."
    return 1
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  local chosen
  if _ensure_whiptail 2>/dev/null; then
    chosen=$(_whiptail_select) || { c_info "No selection made. Exiting."; exit 0; }
    # whiptail returns quoted tokens; strip quotes and newlines
    chosen=$(printf '%s' "$chosen" | tr -d '"' | tr ' ' '\n')
  else
    c_warn "whiptail not available; falling back to numbered list."
    chosen=$(_numbered_select)
  fi

  if [ -z "$chosen" ]; then
    c_info "Nothing selected. Exiting."
    exit 0
  fi

  # If full-dots is among selections, run bootstrap and stop.
  if printf '%s\n' "$chosen" | grep -qx "full-dots"; then
    c_step "Starting full dots install..."
    bash <(curl -fsSL "${DOTS_RAW}/bootstrap.sh")
    exit $?
  fi

  # Install selected tools in registry order (preserves dependency ordering).
  local failed=()
  local key label
  for entry in "${TOOLS[@]}"; do
    IFS='|' read -r key label _ <<< "$entry"
    [ "$key" = "full-dots" ] && continue
    if printf '%s\n' "$chosen" | grep -qx "$key"; then
      _run_remote "$label" "${DOTS_RAW}/scripts/install-${key}.sh" || failed+=("$label")
    fi
  done

  echo
  if [ "${#failed[@]}" -eq 0 ]; then
    c_ok "All done."
  else
    c_warn "Completed with errors. Failed: ${failed[*]}"
    exit 1
  fi
}

main "$@"
