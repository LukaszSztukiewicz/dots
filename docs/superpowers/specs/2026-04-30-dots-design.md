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
│   ├── private_dot_config/                     # ~/.config/ — private_ = chmod 600
│   │   ├── exact_nvim/                         # exact_ on nvim: deletes unmanaged files under ~/.config/nvim/
│   │   └── exact_tmux/                         # exact_ on tmux: deletes unmanaged files under ~/.config/tmux/
│   └── .chezmoitemplates/                      # shared template fragments
│       └── git_identity.tmpl
├── docs/
│   └── superpowers/specs/
└── scripts/                                    # helper scripts; not applied to $HOME
    ├── apply.sh                                # wrapper: ensures valid BW_SESSION, then runs chezmoi apply
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

`home/run_onchange_install-packages.sh.tmpl` is a Chezmoi run script that renders into a plain bash script at apply time — no YAML parsing in the shell.

**How it works:** Chezmoi reads `packages.yaml` during template rendering via `{{ include "../packages.yaml" | fromYaml }}`, iterates the package list, and emits a flat list of distro-specific package names directly into the rendered `.sh` file. The shell only sees a static `apt-get install` call with pre-resolved package names.

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

**Template rendering example** (what the `.tmpl` produces):

```
# run_onchange_install-packages.sh.tmpl
{{- $pkgs := include "../packages.yaml" | fromYaml -}}
{{- $all := $pkgs.packages -}}
{{- if ne .machineRole "server" -}}{{- $all = concat $all $pkgs.workstation_only -}}{{- end -}}
#!/usr/bin/env bash
set -euo pipefail
apt-get install -y \
{{- range $all }}
  {{ .ubuntu }} \
{{- end }}
```

Rendered output (pure bash, no YAML knowledge required at runtime):

```bash
#!/usr/bin/env bash
set -euo pipefail
apt-get install -y \
  ripgrep \
  fzf \
  neovim \
  tmux \
  zsh \
  bat \
```

Chezmoi hashes the rendered script content and only re-executes when the hash changes. Because `packages.yaml` is included via `{{ include }}`, any change to it at the repo root changes the rendered script hash and triggers a re-install on next `chezmoi apply`.

---

## Bootstrap Script (`install.sh`)

Idempotent — safe to re-run on an existing machine. Supports headless execution via environment variables to bypass interactive prompts.

### Headless mode

Environment variables override the machine config prompts (step 5):

```bash
MACHINE_ROLE=server GIT_NAME="Lukasz Sztukiewicz" GIT_EMAIL="ops@example.com" ./install.sh
```

Useful for provisioning via SSH, Ansible, or cloud-init. **Bitwarden auth (step 4) remains interactive** — master password is never passed as an env var.

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
    rev: v8.18.4   # pin to latest stable; update with `pre-commit autoupdate`
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
scripts/apply.sh         # BW-aware apply (see below)
chezmoi cd && git add -A && git commit -m "..." && git push
```

**`scripts/apply.sh` — BW-aware apply wrapper:**

Runs before every `chezmoi apply` to ensure a valid Bitwarden session exists, mirroring the auth logic in `install.sh` without the full bootstrap overhead:

```
1. Check BW_SESSION: run `bw status`
2. If "unlocked" and BW_SESSION is set: proceed directly to chezmoi apply
3. If "locked": run `bw unlock`, export BW_SESSION, then chezmoi apply
4. If "unauthenticated": run `bw login`, then bw unlock, export BW_SESSION, then chezmoi apply
```

A shell function (sourced from `~/.zshrc`) wraps this for convenience:

```bash
# rendered into dot_zshrc.tmpl
cap() { ~/dots/scripts/apply.sh "$@"; }
```

So the daily command is just `cap` (chezmoi apply). The function is rendered into `~/.zshrc` via the template so it's available on every machine automatically.

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
