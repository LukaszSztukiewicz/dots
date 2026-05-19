#!/usr/bin/env bash
set -euo pipefail

# Install fzf from the upstream repo into ~/.fzf and run its installer to set up
# ~/.fzf.zsh (sourced by dot_zshrc.tmpl) with keybindings + completion.
# Re-runnable: pulls the latest if already cloned.
#
# Why upstream instead of OMZ's `fzf` plugin: that plugin tries to source
# /usr/share/doc/fzf/examples/key-bindings.zsh, which is missing or gzipped
# on several Ubuntu/Debian images and breaks shell startup.

FZF_DIR="$HOME/.fzf"

if ! command -v git >/dev/null 2>&1; then
    echo "[dots] git is required to install fzf." >&2
    exit 1
fi

if [ -d "$FZF_DIR/.git" ]; then
    echo "[dots] Updating fzf in $FZF_DIR..."
    git -C "$FZF_DIR" pull --quiet --ff-only || echo "[dots] fzf pull failed; keeping existing clone."
else
    echo "[dots] Cloning fzf to $FZF_DIR..."
    git clone --depth 1 https://github.com/junegunn/fzf.git "$FZF_DIR"
fi

# --bin: compile/download the fzf binary into ~/.fzf/bin
# --key-bindings / --completion: enable Ctrl-T, Ctrl-R, Alt-C and tab completion
# --no-update-rc: don't touch ~/.zshrc — our dot_zshrc.tmpl already sources ~/.fzf.zsh
# --no-bash --no-fish: zsh only for this setup
"$FZF_DIR/install" --key-bindings --completion --no-update-rc --no-bash --no-fish >/dev/null

# Make the upstream fzf binary visible without a new shell.
echo "[dots] fzf installed: $("$FZF_DIR/bin/fzf" --version)"
echo "[dots] Open a new shell or run \`source ~/.fzf.zsh\` to pick up keybindings."
