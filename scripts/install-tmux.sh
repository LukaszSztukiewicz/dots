#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib/colors.sh
. "$(dirname "${BASH_SOURCE[0]:-/dev/null}")/lib/colors.sh" 2>/dev/null || {
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ -z "${DOTS_NO_COLOR:-}" ]; then
        _r=$'\033[0m'; _C=$'\033[36m'; _B=$'\033[34m'; _G=$'\033[32m'; _Y=$'\033[33m'; _R=$'\033[31m'
    else _r=; _C=; _B=; _G=; _Y=; _R=; fi
    c_step(){ printf '%s==>%s %s\n'    "$_C" "$_r" "$*"; }
    c_info(){ printf '%s[dots]%s %s\n' "$_B" "$_r" "$*"; }
    c_ok()  { printf '%s[ ok ]%s %s\n' "$_G" "$_r" "$*"; }
    c_warn(){ printf '%s[warn]%s %s\n' "$_Y" "$_r" "$*" >&2; }
    c_err() { printf '%s[ERR ]%s %s\n' "$_R" "$_r" "$*" >&2; }
}

# Install a static tmux binary into ~/.local/bin/tmux so OSC52 clipboard
# passthrough (allow-passthrough, set-clipboard, terminal-features :clipboard)
# works on systems where the apt-shipped tmux is too old. Ubuntu 22.04 ships
# 3.2a; OSC52 passthrough needs >= 3.3.
#
# No sudo required — drops the binary in $HOME/.local/bin, which dot_zshrc.tmpl
# already prepends to PATH so it shadows /usr/bin/tmux. Re-runnable.
#
# Source: nelsonenzo/tmux-appimage releases. AppImages are self-extracting,
# self-contained ELF binaries — no FUSE / loop mount required at runtime when
# invoked with --appimage-extract-and-run, but we instead extract once and
# install the inner static `tmux` so day-to-day tmux invocations don't pay
# the extract cost.
#
# Override the version via TMUX_VERSION env var. The release tag format is
# `tmux-<version>` (e.g. tmux-3.5a -> tag tmux-3.5a, asset tmux-3.5a-appimage).

TMUX_VERSION="${TMUX_VERSION:-3.5a}"
DEST_BIN="$HOME/.local/bin/tmux"

arch=$(uname -m)
case "$arch" in
    x86_64) ;;
    *)
        c_err "install-tmux.sh: unsupported arch '$arch' (only x86_64 prebuilds available)."
        c_err "Build tmux from source or use the apt package on this host."
        exit 1
        ;;
esac

mkdir -p "$HOME/.local/bin"

asset="tmux-${TMUX_VERSION}-x86_64.appimage"
url="https://github.com/nelsonenzo/tmux-appimage/releases/download/tmux-${TMUX_VERSION}/${asset}"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

c_step "Downloading static tmux ${TMUX_VERSION}..."
curl -fsSL "$url" -o "$TMP/$asset" \
    || { c_err "Download failed. Check https://github.com/nelsonenzo/tmux-appimage/releases for available versions."; exit 1; }

chmod +x "$TMP/$asset"

# AppImage --appimage-extract requires FUSE-less mode of execution. The
# binaries are squashfs-packed; extraction unpacks into ./squashfs-root.
c_info "Extracting appimage..."
(cd "$TMP" && "./$asset" --appimage-extract >/dev/null)

extracted="$TMP/squashfs-root/usr/bin/tmux"
if [ ! -x "$extracted" ]; then
    # Some appimage layouts place the binary at a different path. Probe.
    extracted=$(find "$TMP/squashfs-root" -type f -name tmux -executable | head -1)
fi
[ -x "$extracted" ] || { c_err "Could not locate tmux binary inside the appimage."; exit 1; }

install -m 0755 "$extracted" "$DEST_BIN"

c_ok "tmux installed at $DEST_BIN ($("$DEST_BIN" -V))"
c_info "Open a new shell so PATH picks up ~/.local/bin/tmux ahead of the system tmux."
