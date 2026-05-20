# Dotfiles QoL batch — 2026-05-20

Seven independent improvements to the dotfiles repo. Each is small and can be
implemented and reverted on its own. They are bundled into a single spec
because they share the same files (`install.sh`, `dot_zshrc.tmpl`,
`tmux.conf.tmpl`) and would otherwise create merge conflicts if done in
parallel.

## Items

### 1. Fix TAB completion in zsh

**Symptom.** Pressing `TAB` inserts a literal tab character. It does not
complete commands or files. When pressed mid-command it also clears
`zsh-syntax-highlighting`'s coloring, indicating the line editor redraws but
no completion widget fires.

**Diagnosis.** Either `compinit` is never called (so `^I` defaults to
`self-insert`), or a plugin reorders bindkeys after OMZ initializes
completion. The fix is to assert both states explicitly, after OMZ loads, so
the configuration is robust against plugin-ordering surprises.

**Change.** In `home/dot_zshrc.tmpl`, immediately after the
`source "$ZSH/oh-my-zsh.sh"` line, add:

```zsh
# Force completion init in case OMZ didn't (or a plugin clobbered the binding).
autoload -Uz compinit
compinit -i
bindkey '^I' expand-or-complete
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|=*' 'l:|=* r:|=*'
```

**Verification.** After `chezmoi apply` + new shell:
- `bindkey '^I'` reports `expand-or-complete`.
- `cd ~/` then `ls Doc<TAB>` completes to `Documents/`.
- A second TAB enters menu-select mode (arrow-keys cycle).

### 2. Nested-tmux copy (local tmux ⇒ ssh ⇒ remote tmux)

**Symptom.** Selecting text in *remote* tmux does not land on the local
clipboard. Copying from the remote shell (no remote tmux) works fine.

**Root cause.** OSC52 escape sequences from the remote tmux are not passed
through the local tmux to the terminal emulator. tmux ≥ 3.3 supports this
via `set-clipboard on` + `allow-passthrough on` + clipboard terminal
feature.

**Change A — `home/private_dot_config/exact_tmux/tmux.conf.tmpl`** (apply to
both `laptop` and `workstation` branches; factor common block above the
`if eq .machineRole "laptop"`):

```tmux
set -g set-clipboard on
set -g allow-passthrough on
set -as terminal-features ',*:clipboard'
bind -T copy-mode    MouseDragEnd1Pane send-keys -X copy-pipe-no-clear
bind -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-no-clear
```

**Change B — new `scripts/install-tmux.sh`.** OSC52 passthrough requires
tmux ≥ 3.3. Ubuntu 22.04 ships 3.2a. Rather than depend on apt PPAs (which
require sudo and are not available on locked-down Slurm clusters), install
a static tmux binary into `~/.local/bin/tmux`. Same pattern as
`install-uv.sh` / `install-nvm.sh` — opt-in, no sudo, idempotent.

Source: `https://github.com/nelsonenzo/tmux-appimage/releases` (provides
`tmux.appimage` which is a self-contained static binary). Pin a version via
env var (`TMUX_VERSION`, default `3.5a`). Extract or rename to plain `tmux`,
chmod +x, drop in `~/.local/bin/`. Since `~/.local/bin` is prepended to
PATH by `dot_zshrc.tmpl`, it shadows the system tmux.

Document under the README "Optional language toolchains" section (rename
to "Optional toolchains" if it stops being accurate).

**Verification.** On a host where `tmux -V` reports ≥ 3.3:
- Start local tmux, `ssh` to a remote host, start remote tmux.
- In remote tmux, drag-select text with the mouse.
- Paste into a local browser/editor — text appears.

### 3. zsh as login shell

**Goal.** zsh should be the default login shell, so it's also the default
inside tmux and any other session, not just one terminal.

**Change.** Add a new step to `install.sh` (after step 6, where chezmoi
applies dotfiles, since zsh itself is installed via `packages.yaml`):

```bash
# Step 7. Make zsh the login shell. Best-effort: some clusters disallow
# chsh, in which case we fall back to an `exec zsh -l` trampoline in
# ~/.bash_profile so an interactive bash login still drops into zsh.
_set_login_shell_zsh() {
    local zsh_path current_shell
    zsh_path="$(command -v zsh)" || { info "zsh not installed yet; skipping login-shell change."; return; }
    current_shell="$(getent passwd "$USER" | cut -d: -f7 || true)"
    if [ "$current_shell" = "$zsh_path" ]; then
        info "Login shell already zsh."
        return
    fi
    if grep -qxF "$zsh_path" /etc/shells 2>/dev/null && chsh -s "$zsh_path" 2>/dev/null; then
        info "Login shell set to $zsh_path via chsh."
        return
    fi
    info "chsh unavailable; installing bash -> zsh trampoline in ~/.bash_profile."
    local marker="# dots: exec zsh on interactive bash login"
    if ! grep -qF "$marker" "$HOME/.bash_profile" 2>/dev/null; then
        cat >> "$HOME/.bash_profile" <<EOF

$marker
if [ -t 1 ] && [ -z "\$ZSH_VERSION" ] && command -v zsh >/dev/null; then
    exec zsh -l
fi
EOF
    fi
}
_set_login_shell_zsh
```

**Verification.**
- On a normal machine: `echo $SHELL` after logout/login reports `…/zsh`.
- On a no-sudo cluster: open a fresh ssh session that lands in bash; expect
  immediate `exec zsh -l` and arrival at a zsh prompt.
- `tmux` started from a zsh prompt yields zsh panes.

### 4. p10k instant prompt

**Current state.** `home/dot_p10k.zsh` line 1003 already sets
`POWERLEVEL9K_INSTANT_PROMPT=quiet`, and `home/dot_zshrc.tmpl` lines 2–4
load the cache file. Instant prompt is enabled.

**Action.** Verification only — confirm
`~/.cache/p10k-instant-prompt-*.zsh` exists after one successful prompt
render, and that no warning prints on a second shell. Add a one-line
comment at the top of `dot_zshrc.tmpl` pointing at the p10k setting so
future-us doesn't think it's missing. No behaviour change.

### 5. `scripts/cleanup.sh` — reset + nuke

**New file.** `scripts/cleanup.sh` factors all destructive logic out of
`install.sh` into one auditable place with two modes.

```
Usage: cleanup.sh [--reset | --nuke] [--force]

--reset   Remove install-side state (chezmoi config + source dir, bw and
          chezmoi binaries, bw vault data). Idempotent. Same set as the
          current inline DOTS_RESET block in install.sh. Applied dotfiles
          in $HOME are untouched.

--nuke    Reset, plus:
            applied dotfiles  ~/.zshrc ~/.tmux.conf ~/.p10k.zsh ~/.gitconfig
                              ~/.config/{nvim,tmux,btop}
            OMZ + plugins     ~/.oh-my-zsh
            fzf install       ~/.fzf ~/.fzf.zsh
            language toolchains ~/.local/share/uv ~/.cache/uv ~/.local/bin/{uv,uvx}
                              ~/.nvm ~/miniconda3 ~/.juliaup ~/.sdkman
            caches            ~/.cache/p10k-instant-prompt-*
            shell state       ~/.zsh_history ~/.zcompdump*
            bash trampoline   the marker block in ~/.bash_profile (item 3)
          Confirms with a typed 'NUKE' prompt unless --force or DOTS_NUKE_FORCE=1.

--force   Skip the typed confirmation for --nuke. Useful in headless flows.
```

The exact path list is hard-coded — no glob-rm under `$HOME`. Each path is
removed with `rm -rf -- "$p"` only after an `[ -e "$p" ]` check, so missing
paths are no-ops. The script uses the color helpers from item 7.

**install.sh wiring.** Replace the current inline `DOTS_RESET` block (lines
13–28) with:

```bash
_CLEANUP_SCRIPT="$HOME/.local/share/chezmoi/scripts/cleanup.sh"
if [ "${DOTS_NUKE:-0}" = "1" ]; then
    [ -x "$_CLEANUP_SCRIPT" ] || error "DOTS_NUKE=1 requires the dots repo to be cloned at $_CLEANUP_SCRIPT. Clone first, then re-run."
    "$_CLEANUP_SCRIPT" --nuke ${DOTS_NUKE_FORCE:+--force}
elif [ "${DOTS_RESET:-0}" = "1" ]; then
    if [ -x "$_CLEANUP_SCRIPT" ]; then
        "$_CLEANUP_SCRIPT" --reset
    else
        # Bootstrap path: repo isn't here yet, fall back to inline reset so
        # `curl|bash DOTS_RESET=1` still works on a fresh machine.
        info "DOTS_RESET=1: clearing install state (inline, repo not yet cloned)..."
        reset_paths=(
            "$HOME/.config/chezmoi"
            "$HOME/.local/share/chezmoi"
            "$HOME/.config/Bitwarden CLI"
            "$HOME/.local/bin/bw"
            "$HOME/.local/bin/chezmoi"
        )
        for p in "${reset_paths[@]}"; do
            [ -e "$p" ] && { info "  rm -rf $p"; rm -rf -- "$p"; }
        done
    fi
fi
```

**Note on `curl|bash DOTS_NUKE=1`.** Nuke requires the repo to be present
(it lives *in* the repo). On a never-installed machine there is nothing to
nuke, so the error message is accurate, not a regression.

**Verification.**
- `DOTS_RESET=1 ~/dots/install.sh` → install-side state gone; `$HOME`
  dotfiles intact; re-running install.sh succeeds.
- `~/dots/scripts/cleanup.sh --nuke --force` → applied dotfiles + OMZ + fzf
  + language toolchains gone; the machine is approximately a clean slate.

### 6. Workstation vs laptop visual differentiation

**p10k.** Convert `home/dot_p10k.zsh` → `home/dot_p10k.zsh.tmpl`. The body
is unchanged. At the very end of the file, append a small Chezmoi-templated
override block:

```zsh
# --- dots: machineRole accent ---
{{- if eq .machineRole "laptop" }}
typeset -g POWERLEVEL9K_CONTEXT_DEFAULT_FOREGROUND=39   # cyan
typeset -g POWERLEVEL9K_CONTEXT_DEFAULT_CONTENT_EXPANSION='%n@%m'
typeset -g POWERLEVEL9K_CONTEXT_{DEFAULT,SUDO}_VISUAL_IDENTIFIER_EXPANSION='💻'
{{- else }}
# workstation keeps the existing amber (178) context color set above.
{{- end }}
```

Forcing `_CONTENT_EXPANSION` ensures the context segment is *visible* on
local shells (p10k hides it by default for non-root local sessions —
without this you'd never see the color). The `_VISUAL_IDENTIFIER` line is
plain UTF-8; it renders as a textual marker even without a Nerd Font.

**tmux.** In `tmux.conf.tmpl`, give the laptop variant the same minimal
status bar as workstation but with a laptop accent color (39 cyan vs 166
orange / 136 yellow currently). Specifically, replace the laptop branch
with:

```tmux
{{- if eq .machineRole "laptop" }}
# ... existing laptop bindings ...
set -g status-style bg=colour235,fg=colour39
set -g status-left "#[fg=colour39]💻 #S "
set -g status-right "#[fg=colour39]%Y-%m-%d %H:%M"
{{- else }}
# ... existing workstation block ...
{{- end }}
```

**Verification.**
- `MACHINE_ROLE=laptop` apply: prompt context line shows cyan `user@host
  💻`; tmux status bar is cyan.
- `MACHINE_ROLE=workstation` apply: prompt and tmux look as they do
  today.

### 7. Color-coded installation scripts

**New file `scripts/lib/colors.sh`.** Sourced by every install script.
TTY- and `NO_COLOR`-aware: if stdout isn't a tty or `NO_COLOR` is set,
the helpers emit plain text.

```bash
# scripts/lib/colors.sh — source me, don't execute.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    _c_reset=$'\033[0m'; _c_bold=$'\033[1m'
    _c_red=$'\033[31m'; _c_grn=$'\033[32m'
    _c_ylw=$'\033[33m'; _c_blu=$'\033[34m'
    _c_cyn=$'\033[36m'; _c_gry=$'\033[90m'
else
    _c_reset=; _c_bold=; _c_red=; _c_grn=; _c_ylw=; _c_blu=; _c_cyn=; _c_gry=
fi

c_step() { printf '%s==>%s %s%s%s\n'  "$_c_cyn" "$_c_reset" "$_c_bold" "$*" "$_c_reset"; }
c_info() { printf '%s[dots]%s %s\n'   "$_c_blu" "$_c_reset" "$*"; }
c_ok()   { printf '%s[ ok ]%s %s\n'   "$_c_grn" "$_c_reset" "$*"; }
c_warn() { printf '%s[warn]%s %s\n'   "$_c_ylw" "$_c_reset" "$*" >&2; }
c_err()  { printf '%s[ERR ]%s %s\n'   "$_c_red" "$_c_reset" "$*" >&2; }
```

## Docs cleanup tag-along

`README.md` lines 130–132 currently claim `~/.p10k.zsh` is "not tracked by
chezmoi" — that becomes more wrong once item 6 turns it into a template.
Update those lines in the same commit as item 6.

**Adoption.** Replace `echo "[dots] ..."` and `info()/error()` patterns in:
- `install.sh` (uses local `info`/`error` — keep names, redefine bodies in
  terms of `c_info`/`c_err`)
- All `scripts/install-*.sh`
- `scripts/setup-bw-items.sh`
- `scripts/apply.sh`, `scripts/unmanaged.sh`, `scripts/test.sh`,
  `scripts/bw-with-session.sh`
- `home/run_onchange_*.sh.tmpl` — these run via chezmoi; their output may
  not be on a tty, so the NO_COLOR auto-detect matters.

**Verification.** Run `install.sh` in a normal terminal — output is
colored. Run `install.sh > install.log` — log file is plain. Run with
`NO_COLOR=1` — output is plain.

## Implementation order

Bottom-up, so later items reuse the earlier ones:

1. Item 7 (color lib) — every other script can use it.
2. Item 5 (cleanup.sh) — uses #7's color helpers.
3. Item 3 (login shell) — uses #7.
4. Item 1 (TAB) — pure zshrc edit.
5. Item 6 (visual differentiation) — pure templating.
6. Item 2 (tmux OSC52 + install-tmux.sh) — uses #7 in the new install script.
7. Item 4 (verification + comment only).

Each item is one commit.

## Out of scope

- Updating apt's tmux package on systems that *do* have sudo (the static
  binary route works everywhere; no need for two install paths).
- Changing the p10k theme itself beyond the role-accent override block.
- Migrating any of the run_onchange scripts to scripts/ — they have a
  separate purpose (chezmoi-driven, not user-driven).
