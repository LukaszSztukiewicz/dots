# Dots — Dotfiles Repository Design

**Date:** 2026-04-30
**Tool:** Chezmoi + Bitwarden + per-machine profiles
**Scope:** Multiple Linux machines (workstation, laptop, server) with moderate per-machine variation

---

## Overview

A personal dotfiles repository managed by Chezmoi. It covers a broad set of tools (zsh, git, neovim, tmux, dev tools), handles per-machine differences via local config variables and Go templates, pulls secrets from Bitwarden at apply time, and enforces a clean system state via targeted `exact_` prefixes on specific tool directories. A single `install.sh` script bootstraps a new machine end-to-end, supporting both interactive and headless (env-var-driven) execution.

---

## Repository Structure

```
dots/
├── README.md
├── install.sh                                  # bootstrap: installs chezmoi, bw, handles bw auth, writes local config, runs apply
├── packages.yaml                               # canonical package list with Ubuntu/distro-specific overrides
├── home/                                       # chezmoi source directory
│   ├── .chezmoi.toml.tmpl                      # generates per-machine ~/.config/chezmoi/chezmoi.toml
│   ├── .chezmoiignore                          # excludes README.md, scripts/, docs/ from $HOME apply
│   ├── run_onchange_install-packages.sh.tmpl   # installs packages; re-runs only when packages.yaml changes
│   ├── dot_gitconfig.tmpl                      # ~/.gitconfig — Bitwarden (bitwardenFields) + machine vars
│   ├── dot_zshrc.tmpl                          # ~/.zshrc
│   ├── dot_tmux.conf                           # ~/.tmux.conf (no templating needed)
│   ├── private_dot_config/                     # ~/.config/ — private_ = chmod 600
│   │   ├── exact_nvim/                         # exact_ on nvim: deletes unmanaged files under ~/.config/nvim/
│   │   └── exact_tmux/                         # exact_ on tmux: deletes unmanaged files under ~/.config/tmux/
│   └── .chezmoitemplates/                      # shared template fragments
│       └── git_identity.tmpl
├── docs/
│   └── superpowers/specs/
└── scripts/                                    # helper scripts; not applied to $HOME
    ├── test.sh                                 # Docker-based smoke test
    └── unmanaged.sh                            # runs chezmoi unmanaged to surface files not yet tracked
```

### Key Chezmoi Naming Conventions

| Prefix/Suffix | Meaning |
|---|---|
| `dot_` | Renamed to `.` on apply (`dot_zshrc` → `~/.zshrc`) |
| `private_` | Applied with `chmod 600` |
| `exact_` | Deletes files in destination not present in source (scoped to that directory) |
| `.tmpl` suffix | Processed as Go template before writing |
| `run_onchange_` | Script runs only when its content (or hashed inputs) change |

**`exact_` scoping:** Applied at the specific tool directory level (`exact_nvim/`, `exact_tmux/`) rather than at `~/.config/` itself. This prevents Chezmoi from deleting unmanaged directories in `~/.config/` that belong to other tools.

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
# install minimal server packages from packages.yaml
{{ else -}}
# install full workstation packages from packages.yaml
{{ end -}}
```

---

## Secrets Management

Secrets are never committed to the repo. They are pulled from Bitwarden at `chezmoi apply` time.

### Performance: `bitwardenFields` over repeated `bitwarden` calls

Each `bitwarden` template call spawns a new `bw` (Node.js) process. For multiple secrets, use `bitwardenFields` once per Bitwarden item to fetch all custom fields as a dictionary — Chezmoi caches the result for the apply session:

```
# dot_gitconfig.tmpl — ONE bw call for all git-related secrets
{{- $gitSecrets := bitwardenFields "item" "dots-git-secrets" -}}
[credential]
  helper = {{ $gitSecrets.credential_helper.value }}
```

**Bitwarden item structure:** Group secrets by domain (e.g., one item `dots-git-secrets` with custom fields `credential_helper`, `signing_key`). Avoid one item per secret.

### Auth flow

Chezmoi reads `BW_SESSION` from the environment. `install.sh` handles the session before invoking `chezmoi apply` (see Bootstrap section). The `private_` prefix on managed files ensures sensitive files are `chmod 600` on disk.

---

## Package Management

`home/run_onchange_install-packages.sh.tmpl` is a Chezmoi run script that:

1. Detects the distro's package manager (currently focused on Ubuntu/apt; structure allows adding pacman/dnf later).
2. Reads `packages.yaml` for the package list, which maps packages to distro-specific names.
3. Branches on `machineRole` to skip workstation-only packages on servers.

**`packages.yaml` structure (Ubuntu-focused):**

```yaml
packages:
  - name: ripgrep
    ubuntu: ripgrep
  - name: fzf
    ubuntu: fzf
  - name: neovim
    ubuntu: neovim
  - name: tmux
    ubuntu: tmux
  - name: zsh
    ubuntu: zsh
workstation_only:
  - name: bat
    ubuntu: bat
```

Chezmoi hashes the script content and only re-executes when the hash changes. The script embeds `{{ include "../packages.yaml" }}` so that any change to `packages.yaml` at the repo root triggers a re-install on next `chezmoi apply`.

---

## Bootstrap Script (`install.sh`)

Idempotent — safe to re-run on an existing machine. Supports headless execution via environment variables to bypass interactive prompts.

### Headless mode

Environment variables override all interactive prompts:

```bash
MACHINE_ROLE=server GIT_NAME="Lukasz Sztukiewicz" GIT_EMAIL="ops@example.com" ./install.sh
```

Useful for provisioning via SSH, Ansible, or cloud-init.

### Flow

```
1. Detect OS / package manager (currently Ubuntu/apt)
2. Install chezmoi if not present (official curl installer)
3. Install Bitwarden CLI (bw) if not present
4. Handle Bitwarden auth:
   a. Run `bw status`
   b. If "unauthenticated": prompt for email + master password, run `bw login`
   c. If "locked": run `bw unlock`, capture session token
   d. Export BW_SESSION so chezmoi templates can call bitwardenFields
5. If ~/.config/chezmoi/chezmoi.toml does not exist:
   a. Use env vars if set; otherwise prompt for: machineRole, gitName, gitEmail, proxy (optional)
   b. Write ~/.config/chezmoi/chezmoi.toml
6. chezmoi init --apply https://github.com/<user>/dots
   (or a local path for offline use)
```

Re-running on an existing machine skips steps 2–3, re-checks Bitwarden auth (step 4), skips step 5 if `chezmoi.toml` already exists, and runs `chezmoi apply`.

---

## Security: Secret Leak Prevention

Even with Bitwarden, hardcoded tokens can accidentally end up in `.tmpl` files. A pre-commit hook using **gitleaks** prevents this from being pushed.

**`.pre-commit-config.yaml`** (at repo root):

```yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.x.x
    hooks:
      - id: gitleaks
```

Setup: `pip install pre-commit && pre-commit install`. CI also runs `gitleaks detect` on every push as a second line of defence.

---

## Testing & Validation

### Day-to-day workflow

```bash
chezmoi edit ~/.zshrc    # open managed file in editor
chezmoi diff             # preview what apply would change
chezmoi apply            # apply changes to $HOME
chezmoi cd && git add -A && git commit -m "..." && git push
```

### State pruning (`scripts/unmanaged.sh`)

Runs `chezmoi unmanaged` to list files in `$HOME` not yet tracked by Chezmoi. Run occasionally to identify configs worth bringing under management.

### Docker smoke test (`scripts/test.sh`)

Spins up an Ubuntu container, runs `install.sh` with a mock `bw` stub (returns fixture data for all `bitwardenFields` calls), and validates that key files are present and correctly rendered. Exits non-zero on any failure.

### CI (GitHub Actions)

Runs on every push to `main`:
- Docker smoke test (Ubuntu)
- `shellcheck` on all `.sh` files
- `gitleaks detect` for secret scanning
- No real Bitwarden credentials needed — `bw` is stubbed

---

## Error Handling

- `install.sh` uses `set -euo pipefail` throughout; any failure aborts with a clear message.
- Bitwarden auth failures in `install.sh` print the `bw status` output and exit with a descriptive error.
- Chezmoi template errors surface at `chezmoi apply` time with file and line context.
- Missing Bitwarden items cause `chezmoi apply` to fail loudly — no silent fallback to empty secrets.

---

## Out of Scope

- macOS support (not needed currently; Chezmoi supports it if added later)
- GUI application configs (browser profiles, desktop environment settings)
- SSH key generation (keys are stored in Bitwarden and retrieved separately)
- Non-Ubuntu distros (structure supports adding them to `packages.yaml` later)
