# Dots — Dotfiles Repository Design

**Date:** 2026-04-30
**Tool:** Chezmoi + Bitwarden + per-machine profiles
**Scope:** Multiple Linux machines (workstation, laptop, server) with moderate per-machine variation

---

## Overview

A personal dotfiles repository managed by Chezmoi. It covers a broad set of tools (zsh, git, neovim, tmux, dev tools), handles per-machine differences via local config variables and Go templates, pulls secrets from Bitwarden at apply time, and enforces a clean system state via the `exact_` prefix. A single `install.sh` script bootstraps a new machine end-to-end.

---

## Repository Structure

```
dots/
├── README.md
├── install.sh                                  # bootstrap: installs chezmoi, bw, writes local config, runs apply
├── home/                                       # chezmoi source directory
│   ├── .chezmoi.toml.tmpl                      # generates per-machine ~/.config/chezmoi/chezmoi.toml
│   ├── .chezmoiignore                          # excludes README.md, scripts/, docs/ from $HOME apply
│   ├── run_onchange_install-packages.sh.tmpl   # installs packages; re-runs only when packages.txt changes
│   ├── packages.txt                            # canonical package list (hashed by run_onchange_)
│   ├── dot_gitconfig.tmpl                      # ~/.gitconfig — Bitwarden + machine vars
│   ├── dot_zshrc.tmpl                          # ~/.zshrc
│   ├── dot_tmux.conf                           # ~/.tmux.conf (no templating)
│   ├── exact_private_dot_config/               # ~/.config/ — exact_ deletes unmanaged files; private_ = chmod 600
│   │   └── nvim/
│   └── .chezmoitemplates/                      # shared template fragments
│       └── git_identity.tmpl
├── docs/
│   └── superpowers/specs/
└── scripts/                                    # helper scripts; not applied to $HOME
    └── test.sh                                 # Docker-based smoke test
```

### Key Chezmoi Naming Conventions

| Prefix/Suffix | Meaning |
|---|---|
| `dot_` | Renamed to `.` on apply (`dot_zshrc` → `~/.zshrc`) |
| `private_` | Applied with `chmod 600` |
| `exact_` | Deletes files in destination not present in source |
| `.tmpl` suffix | Processed as Go template before writing |
| `run_onchange_` | Script runs only when its content (or hashed inputs) change |

---

## Per-Machine Configuration

Each machine has a local `~/.config/chezmoi/chezmoi.toml` (not committed). The repo's `.chezmoi.toml.tmpl` generates a starter version on first `chezmoi init`.

### Local config schema

```toml
[data]
  machineRole = "workstation"   # workstation | server | laptop
  gitName     = "Lukasz Sztukiewicz"
  gitEmail    = "work@example.com"
  proxy       = ""              # non-empty on machines that need an HTTP proxy
```

### Template usage

Templates reference data variables and branch on `machineRole`:

```
# dot_gitconfig.tmpl
[user]
  name  = {{ .gitName }}
  email = {{ .gitEmail }}

{{ if .proxy -}}
[http]
  proxy = {{ .proxy }}
{{ end -}}
```

```
# run_onchange_install-packages.sh.tmpl
{{ if eq .machineRole "server" -}}
# install minimal server packages from packages.txt
{{ else -}}
# install full workstation packages from packages.txt
{{ end -}}
```

---

## Secrets Management

Secrets are never committed to the repo. They are pulled from Bitwarden at `chezmoi apply` time.

- Chezmoi calls `bw get` / `bw list` via built-in Bitwarden template functions.
- `bw unlock` is invoked once per session by chezmoi and the session token is cached.
- Template syntax: `{{ (bitwarden "item" "github-token").notes }}`
- The `private_` prefix on managed files ensures sensitive files are `chmod 600` on disk.

---

## Package Management

`home/run_onchange_install-packages.sh.tmpl` is a Chezmoi run script that:

1. Detects the distro's package manager (apt, pacman, dnf).
2. Reads `packages.txt` for the list of packages to install.
3. Branches on `machineRole` to optionally install workstation-only packages.

Chezmoi hashes the script content (which includes `packages.txt` via template inclusion) and only re-executes when the hash changes — so adding or removing a package from `packages.txt` automatically triggers a re-install on next `chezmoi apply`.

---

## Bootstrap Script (`install.sh`)

Idempotent — safe to re-run on an existing machine.

```
Flow:
1. Detect OS / package manager
2. Install chezmoi if not present (official curl installer)
3. Install Bitwarden CLI (bw) if not present
4. If ~/.config/chezmoi/chezmoi.toml does not exist:
   a. Prompt for: machineRole, gitName, gitEmail, proxy (optional)
   b. Write ~/.config/chezmoi/chezmoi.toml
5. chezmoi init --apply https://github.com/<user>/dots
   (or a local path for offline use)
```

Re-running on an existing machine skips steps 2–4 and runs `chezmoi apply` directly.

---

## Testing & Validation

### Day-to-day workflow

```bash
chezmoi edit ~/.zshrc    # open managed file in editor
chezmoi diff             # preview what apply would change
chezmoi apply            # apply changes to $HOME
chezmoi cd && git add -A && git commit -m "..." && git push
```

### Docker smoke test (`scripts/test.sh`)

Spins up Debian and Arch containers, runs `install.sh` in each with a mock `bw` stub (returns fixture data), and validates that key files are present and correctly rendered. Exits non-zero on any failure.

### CI (GitHub Actions)

Runs on every push to `main`:
- Docker smoke test (Debian + Arch)
- `shellcheck` on all `.sh` files
- No real Bitwarden credentials needed — `bw` is stubbed

---

## Error Handling

- `install.sh` uses `set -euo pipefail` throughout; any failure aborts with a clear message.
- Chezmoi template errors surface at `chezmoi apply` time with file and line context.
- Missing Bitwarden items cause `chezmoi apply` to fail loudly — no silent fallback to empty secrets.

---

## Out of Scope

- macOS support (not needed currently; Chezmoi supports it if added later)
- GUI application configs (browser profiles, desktop environment settings)
- SSH key generation (keys are stored in Bitwarden and retrieved separately)
