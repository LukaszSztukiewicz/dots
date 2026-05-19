# Shell stack + opt-in language toolchains — design

Date: 2026-05-19
Status: approved

## Purpose

Distill a working developer machine's `~/.zshrc`, tmux config, and version-manager init blocks into the dots repo so a fresh machine reproduces the same prompt, completion, fuzzy-finder, and editor behaviour. Make installing language version managers (nvm, sdkman, juliaup, uv, conda) a one-command opt-in, not a default.

## Scope

In scope:

- Full rewrite of `home/dot_zshrc.tmpl` to layer Oh My Zsh + plugins + Powerlevel10k + fzf integration + guarded version-manager init blocks on top of the existing chezmoi helpers and proxy template.
- New `home/run_onchange_install-omz.sh.tmpl` that clones OMZ, the five plugins, and powerlevel10k into `~/.oh-my-zsh/` on `chezmoi apply` if missing.
- New `home/private_dot_config/tmux/tmux.conf` matching the user's existing tmux setup.
- Add `fd-find` to `packages.yaml` and create a `~/.local/bin/fd → fdfind` shim during package install (Ubuntu quirk).
- Five thin scripts under `scripts/install-{nvm,sdkman,juliaup,uv,conda}.sh`, each a wrapper around the upstream installer. Each script is idempotent and safe to re-run.
- README: a new "Optional language toolchains" subsection listing the five scripts.

Out of scope:

- Machine-specific PATH entries (`/opt/nvim-...`, `~/INSTALLATIONS/bin`, hardcoded `/home/lsztuk/...`).
- Shipping a `.p10k.zsh` — user runs `p10k configure` once per machine.
- `[user]` block in `.gitconfig` — already templated from install.sh.
- Pinning upstream version-manager installer versions (deferred; current commit uses `latest`).

## Architecture

### Layering inside `dot_zshrc.tmpl`

Order is load-bearing:

1. Powerlevel10k instant prompt (must be near the very top, guarded by file existence).
2. Oh My Zsh — `ZSH=$HOME/.oh-my-zsh`, `plugins=(...)`, source `oh-my-zsh.sh` if present.
3. Powerlevel10k theme — source from `$ZSH/custom/themes/powerlevel10k/...` if present, then `~/.p10k.zsh` if present.
4. Shell options + history (existing content preserved).
5. Editor env vars (`EDITOR`/`VISUAL`/`GIT_EDITOR` = `vim`, already shipped).
6. FZF env vars (`FZF_DEFAULT_COMMAND` + `_CTRL_T_*` + `_ALT_C_*` + preview opts).
7. chezmoi helpers (`cap`, `cdots` — preserved).
8. Proxy template block (preserved).
9. Version-manager init blocks (each guarded by `[ -d ~/.foo ]` or `[ -f ... ]`):
   - uv (`. "$HOME/.local/bin/env"`)
   - nvm
   - juliaup (PATH prepend)
   - conda
   - **sdkman last** (upstream requires it)

A missing manager costs zero startup time — its block is a single `[` test.

### `run_onchange_install-omz.sh.tmpl`

Follows the same pattern as the existing `run_onchange_install-packages.sh.tmpl`. One `clone_if_missing` helper, then six calls (OMZ + five plugins + p10k theme). All clones are `--depth 1`. Re-running is a no-op once everything is present. No updates are pulled — users can `cd ~/.oh-my-zsh && git pull` manually.

Plugin URLs:
- `zsh-users/zsh-autosuggestions`
- `zsh-users/zsh-syntax-highlighting`
- `MichaelAquilina/zsh-you-should-use` (canonical; clone target dir is still `$ZSH_CUSTOM/plugins/you-should-use` so the OMZ `plugins=(...you-should-use...)` line keeps working).
- `fdellwing/zsh-bat`
- `jeffreytse/zsh-vi-mode`
- Theme: `romkatv/powerlevel10k`

### Tmux config

`home/private_dot_config/tmux/tmux.conf` — verbatim copy of the user's eight lines: C-Space prefix, mouse, scrollwheel-aware copy-mode binding, 50k history, 10ms escape-time. Chezmoi's `private_` prefix is unnecessary for tmux but matches the existing nvim path convention in the repo.

### `fd` shim

Ubuntu's `fd-find` package installs the binary as `fdfind`. The fzf env vars assume `fd`. Two options:

- Add a `~/.local/bin/fd` symlink during package install (chosen — keeps env vars portable to non-Ubuntu).
- Use `fdfind` in the env vars (rejected — non-portable).

The symlink creation happens inside the existing `run_onchange_install-packages.sh.tmpl` (or its successor) after `fd-find` is installed. If that script isn't easily extensible, add a tiny `run_once_after_install-packages_fd-shim.sh` instead.

### Language-manager installers (`scripts/install-*.sh`)

Each script:

1. Runs the upstream installer (`curl ... | bash` or `wget` equivalent).
2. Does not modify the user's `.zshrc` — the init block is already there, guarded.
3. Is safe to re-run (upstream installers themselves are idempotent).
4. Prints a one-line success message + reminder to open a new shell.

Concrete URLs:

- nvm — `https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh`
- sdkman — `https://get.sdkman.io`
- juliaup — `https://install.julialang.org`
- uv — `https://astral.sh/uv/install.sh`
- conda — Miniconda installer for the current arch, ran with `-b -p $HOME/miniconda3`

## Error handling

- `run_onchange_install-omz.sh.tmpl` uses `set -euo pipefail` and aborts on first failure (typical for chezmoi run_onchange scripts).
- Each `scripts/install-*.sh` aborts on network errors via `set -euo pipefail` and `curl -fsSL`.
- The zshrc init blocks are pure file-existence checks, so a partial/failed install of any manager doesn't break shell startup.

## Testing

- Existing `scripts/test.sh` smoke test should still pass (it bypasses install.sh and only exercises `chezmoi apply` against the `home/` source tree).
- Manual verification: `DOTS_RESET=1 curl -fsSL .../install.sh | bash` on a fresh Ubuntu container should produce a usable p10k prompt after one `chezmoi apply`, with all five language-manager blocks silent until the corresponding `scripts/install-*.sh` is run.

## Open items / future work

- Pinning version-manager installer versions (sha-pinned URLs or explicit version vars).
- A combined `scripts/install-langs.sh` that calls a chosen subset (low-priority once per-tool scripts exist).
- Plugin updates — currently manual; a future `scripts/update-omz.sh` could `git -C $each pull`.
