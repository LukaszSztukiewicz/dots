# Dots — Dotfiles Repository Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Chezmoi-managed dotfiles repository for multiple Ubuntu machines, with Bitwarden secrets, per-machine profiles, package management, secret-leak prevention, and a smooth daily apply workflow.

**Architecture:** Chezmoi uses `home/` as its source directory. Templates render using machine-local variables from `~/.config/chezmoi/chezmoi.toml` (not committed) and secrets fetched via `bitwardenFields` (one `bw` process per Bitwarden item, result cached for the session). Shell scripts in `scripts/` are helpers — never applied to `$HOME`.

**Tech Stack:** Chezmoi, Bitwarden CLI (`bw`), bash (`set -euo pipefail`), Go templates (via Chezmoi), gitleaks, shellcheck, Docker (smoke tests), GitHub Actions (CI).

---

## File Map

| File | Responsibility |
|---|---|
| `packages.yaml` | Canonical package list with Ubuntu-specific names; consumed by Chezmoi template at render time |
| `home/.chezmoi.toml.tmpl` | Auto-generates starter `~/.config/chezmoi/chezmoi.toml` on first `chezmoi init` |
| `home/.chezmoiignore` | Prevents `docs/`, `scripts/`, `README.md`, `packages.yaml` from being written to `$HOME` |
| `home/.chezmoitemplates/git_identity.tmpl` | Shared Go template fragment: git `[user]` block |
| `home/dot_gitconfig.tmpl` | Renders `~/.gitconfig` — pulls secrets via `bitwardenFields`, includes git identity fragment |
| `home/dot_zshrc.tmpl` | Renders `~/.zshrc` — includes `cap` shell function pointing to `scripts/apply.sh` |
| `home/private_dot_config/exact_nvim/init.lua` | Minimal Neovim config scaffold (chmod 600, exact-managed) |
| `home/private_dot_config/exact_tmux/tmux.conf` | Minimal Tmux config scaffold (chmod 600, exact-managed) |
| `home/run_onchange_install-packages.sh.tmpl` | Renders to a static `apt-get install` script; re-runs when `packages.yaml` changes |
| `scripts/apply.sh` | BW-aware apply wrapper: checks `bw status`, unlocks/logs in, then runs `chezmoi apply` |
| `scripts/unmanaged.sh` | Prints `chezmoi unmanaged` output for periodic state-pruning review |
| `install.sh` | Full bootstrap: installs chezmoi + bw, BW auth, writes `chezmoi.toml`, runs `chezmoi init --apply` |
| `.pre-commit-config.yaml` | Gitleaks pre-commit hook to catch accidental secret commits |
| `scripts/test.sh` | Docker-based smoke test: spins Ubuntu container, stubs `bw`, runs apply, asserts key files |
| `.github/workflows/ci.yml` | CI: shellcheck, gitleaks scan, Docker smoke test on every push to `main` |
| `README.md` | Setup instructions: prerequisites, first-time bootstrap, day-to-day workflow |

---

## Task 1: Scaffold directory structure and initialise Chezmoi for local development

**Files:**
- Create: `home/private_dot_config/exact_nvim/` (directory)
- Create: `home/private_dot_config/exact_tmux/` (directory)
- Create: `home/.chezmoitemplates/` (directory)
- Create: `scripts/` (directory)
- Create: `.github/workflows/` (directory)

- [ ] **Step 1: Create all directories**

```bash
mkdir -p home/private_dot_config/exact_nvim
mkdir -p home/private_dot_config/exact_tmux
mkdir -p home/.chezmoitemplates
mkdir -p scripts
mkdir -p .github/workflows
```

- [ ] **Step 2: Verify chezmoi is installed**

```bash
chezmoi --version
```

Expected: version string like `chezmoi version v2.x.x`. If not installed:
```bash
sh -c "$(curl -fsLS get.chezmoi.io)"
```

- [ ] **Step 3: Create a development-time local chezmoi config**

This points chezmoi at `home/` for local development. It is machine-local and never committed.

```bash
mkdir -p ~/.config/chezmoi
cat > ~/.config/chezmoi/chezmoi.toml << 'EOF'
sourceDir = "/home/lsztuk/CLAUDE_SANDBOX/dots/home"

[data]
  machineRole = "workstation"
  gitName     = "Lukasz Sztukiewicz"
  gitEmail    = "test@example.com"
  proxy       = ""
EOF
```

Replace `/home/lsztuk/CLAUDE_SANDBOX/dots` with the actual repo path if different.

- [ ] **Step 4: Commit the scaffolded directories**

```bash
git add home/ scripts/ .github/
git commit -m "chore: scaffold directory structure"
```

---

## Task 2: `packages.yaml`

**Files:**
- Create: `packages.yaml`

- [ ] **Step 1: Create `packages.yaml`**

```yaml
packages:
  - name: zsh
    ubuntu: zsh
  - name: git
    ubuntu: git
  - name: curl
    ubuntu: curl
  - name: tmux
    ubuntu: tmux
  - name: neovim
    ubuntu: neovim
  - name: ripgrep
    ubuntu: ripgrep
  - name: fzf
    ubuntu: fzf
  - name: python3
    ubuntu: python3

workstation_only:
  - name: bat
    ubuntu: bat
  - name: jq
    ubuntu: jq
```

- [ ] **Step 2: Validate it is parseable YAML**

```bash
python3 -c "import yaml, sys; yaml.safe_load(open('packages.yaml')); print('OK')"
```

Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add packages.yaml
git commit -m "chore: add packages.yaml with Ubuntu package list"
```

---

## Task 3: `home/.chezmoiignore`

**Files:**
- Create: `home/.chezmoiignore`

- [ ] **Step 1: Create `.chezmoiignore`**

This file lives inside the chezmoi source directory (`home/`) and tells Chezmoi which source files to skip when applying to `$HOME`. Without it, Chezmoi would try to write `README.md`, `packages.yaml`, etc. into the home directory.

```
# repo-level files that must not be written to $HOME
../README.md
../packages.yaml
../scripts
../docs
../.github
../.pre-commit-config.yaml
```

- [ ] **Step 2: Verify Chezmoi acknowledges the ignore file**

```bash
chezmoi status 2>&1 | head -20
```

Expected: no output or only lines for files inside `home/` — no mention of `README.md` or `packages.yaml`.

- [ ] **Step 3: Commit**

```bash
git add home/.chezmoiignore
git commit -m "chore: add .chezmoiignore to prevent repo files landing in \$HOME"
```

---

## Task 4: `home/.chezmoi.toml.tmpl`

**Files:**
- Create: `home/.chezmoi.toml.tmpl`

This template generates a starter `~/.config/chezmoi/chezmoi.toml` on `chezmoi init`. It runs once on first init; subsequent re-inits skip it if the file already exists.

- [ ] **Step 1: Create the template**

```
{{- $machineRole := promptStringOnce . "machineRole" "Machine role (workstation/server/laptop)" -}}
{{- $gitName := promptStringOnce . "gitName" "Git full name" -}}
{{- $gitEmail := promptStringOnce . "gitEmail" "Git email" -}}
{{- $proxy := promptStringOnce . "proxy" "HTTP proxy (leave blank if none)" -}}

[data]
  machineRole = {{ $machineRole | quote }}
  gitName     = {{ $gitName | quote }}
  gitEmail    = {{ $gitEmail | quote }}
  proxy       = {{ $proxy | quote }}
```

`promptStringOnce` reads an existing value from the current config if present, otherwise prompts the user. This means re-running `chezmoi init` on an existing machine won't re-prompt.

- [ ] **Step 2: Verify the template renders without error using current dev config**

```bash
chezmoi execute-template --init < home/.chezmoi.toml.tmpl
```

Expected: TOML output with values from `~/.config/chezmoi/chezmoi.toml` (no prompts since values already exist):
```toml
[data]
  machineRole = "workstation"
  gitName     = "Lukasz Sztukiewicz"
  gitEmail    = "test@example.com"
  proxy       = ""
```

- [ ] **Step 3: Commit**

```bash
git add home/.chezmoi.toml.tmpl
git commit -m "feat: add .chezmoi.toml.tmpl for per-machine config generation"
```

---

## Task 5: Git identity template fragment and `dot_gitconfig.tmpl`

**Files:**
- Create: `home/.chezmoitemplates/git_identity.tmpl`
- Create: `home/dot_gitconfig.tmpl`

- [ ] **Step 1: Create the shared git identity template fragment**

```
{{- define "git_identity" -}}
[user]
    name  = {{ .gitName }}
    email = {{ .gitEmail }}
{{- end }}
```

Save to `home/.chezmoitemplates/git_identity.tmpl`.

- [ ] **Step 2: Create `home/dot_gitconfig.tmpl`**

```
{{- $gitSecrets := bitwardenFields "item" "dots-git-secrets" -}}
{{ template "git_identity" . }}

[core]
    editor = nvim

[init]
    defaultBranch = main

[pull]
    rebase = true

[credential]
    helper = {{ (index $gitSecrets "credential_helper").value }}

{{ if .proxy -}}
[http]
    proxy = {{ .proxy }}
{{ end -}}
```

**Bitwarden prerequisite:** Create a Bitwarden item named `dots-git-secrets` with one custom field:
- Field name: `credential_helper`, value: `store` (or your preferred git credential helper)

- [ ] **Step 3: Verify template renders — with bw session active**

If `BW_SESSION` is set and `bw` is unlocked:
```bash
chezmoi execute-template < home/dot_gitconfig.tmpl
```

Expected: rendered `~/.gitconfig` content with your name, email, and credential helper substituted.

If not testing Bitwarden right now, skip this step and verify during the smoke test (Task 14).

- [ ] **Step 4: Commit**

```bash
git add home/.chezmoitemplates/git_identity.tmpl home/dot_gitconfig.tmpl
git commit -m "feat: add dot_gitconfig.tmpl with bitwardenFields and machine vars"
```

---

## Task 6: `home/dot_zshrc.tmpl`

**Files:**
- Create: `home/dot_zshrc.tmpl`

- [ ] **Step 1: Create `home/dot_zshrc.tmpl`**

```bash
# --- core shell options ---
setopt AUTO_CD
setopt HIST_IGNORE_DUPS
HISTSIZE=10000
SAVEHIST=10000
HISTFILE=~/.zsh_history

# --- prompt ---
autoload -Uz promptinit && promptinit
prompt default

# --- fzf ---
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# --- chezmoi / dots helpers ---
# cap: BW-aware chezmoi apply wrapper
cap() {
    "$(chezmoi source-path)/../scripts/apply.sh" "$@"
}

# cdots: jump to chezmoi source directory
alias cdots='cd "$(chezmoi source-path)/.."'

{{ if .proxy -}}
# proxy
export http_proxy={{ .proxy }}
export https_proxy={{ .proxy }}
export no_proxy=localhost,127.0.0.1
{{ end -}}
```

- [ ] **Step 2: Render the template and verify output**

```bash
chezmoi execute-template < home/dot_zshrc.tmpl
```

Expected: a valid shell script with `cap()` function and `cdots` alias. No proxy block (since `proxy = ""`).

- [ ] **Step 3: Commit**

```bash
git add home/dot_zshrc.tmpl
git commit -m "feat: add dot_zshrc.tmpl with cap apply wrapper and cdots alias"
```

---

## Task 7: Neovim config scaffold

**Files:**
- Create: `home/private_dot_config/exact_nvim/init.lua`

The `exact_` prefix on this directory means Chezmoi will delete any files under `~/.config/nvim/` that are not present in `exact_nvim/`. The `private_` prefix on the parent `private_dot_config/` ensures `~/.config/` is created with mode 700.

- [ ] **Step 1: Create a minimal `init.lua`**

```lua
-- neovim base config
vim.g.mapleader = " "

vim.opt.number         = true
vim.opt.relativenumber = true
vim.opt.expandtab      = true
vim.opt.shiftwidth     = 2
vim.opt.tabstop        = 2
vim.opt.termguicolors  = true
vim.opt.ignorecase     = true
vim.opt.smartcase      = true
vim.opt.splitright     = true
vim.opt.splitbelow     = true
```

Save to `home/private_dot_config/exact_nvim/init.lua`.

- [ ] **Step 2: Verify chezmoi sees the file**

```bash
chezmoi status
```

Expected: a line like `A  /home/<user>/.config/nvim/init.lua` (or similar, meaning it will be added).

- [ ] **Step 3: Commit**

```bash
git add home/private_dot_config/exact_nvim/init.lua
git commit -m "feat: add minimal neovim config scaffold"
```

---

## Task 8: Tmux config scaffold

**Files:**
- Create: `home/private_dot_config/exact_tmux/tmux.conf`

Tmux reads `$XDG_CONFIG_HOME/tmux/tmux.conf` (defaults to `~/.config/tmux/tmux.conf`) before the legacy `~/.tmux.conf`. Using the XDG path keeps everything under `~/.config/`.

- [ ] **Step 1: Create `tmux.conf`**

```
# -- general --
set -g default-terminal "tmux-256color"
set -ga terminal-overrides ",xterm-256color:Tc"
set -g history-limit 10000
set -g mouse on
set -g base-index 1
setw -g pane-base-index 1

# -- prefix --
unbind C-b
set -g prefix C-a
bind C-a send-prefix

# -- splits --
bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"

# -- reload config --
bind r source-file ~/.config/tmux/tmux.conf \; display "Config reloaded"

# -- status bar --
set -g status-style bg=colour235,fg=colour136
set -g status-left "#[fg=colour166]#S "
set -g status-right "#[fg=colour136]%Y-%m-%d %H:%M"
```

Save to `home/private_dot_config/exact_tmux/tmux.conf`.

- [ ] **Step 2: Verify chezmoi sees the file**

```bash
chezmoi status
```

Expected: `A  /home/<user>/.config/tmux/tmux.conf` in the output.

- [ ] **Step 3: Commit**

```bash
git add home/private_dot_config/exact_tmux/tmux.conf
git commit -m "feat: add minimal tmux config scaffold (XDG path)"
```

---

## Task 9: `home/run_onchange_install-packages.sh.tmpl`

**Files:**
- Create: `home/run_onchange_install-packages.sh.tmpl`

Chezmoi hashes the rendered script content. Because `packages.yaml` is pulled in via `{{ include }}`, any change to it changes the hash and triggers a re-run on next `chezmoi apply`.

- [ ] **Step 1: Create the template**

```bash
{{- $pkgs := include "../packages.yaml" | fromYaml -}}
{{- $all := $pkgs.packages -}}
{{- if ne .machineRole "server" -}}
{{-   $all = concat $all $pkgs.workstation_only -}}
{{- end -}}
#!/usr/bin/env bash
set -euo pipefail

echo "[dots] Installing packages..."
sudo apt-get update -qq
sudo apt-get install -y \
{{- range $i, $pkg := $all }}
  {{ $pkg.ubuntu }}{{ if lt (add1 $i) (len $all) }} \{{ end }}
{{- end }}

echo "[dots] Package installation complete."
```

Save to `home/run_onchange_install-packages.sh.tmpl`.

- [ ] **Step 2: Render the template and verify output**

```bash
chezmoi execute-template < home/run_onchange_install-packages.sh.tmpl
```

Expected: a valid bash script with a flat `apt-get install -y` list. For `machineRole = "workstation"` this includes both `packages` and `workstation_only` entries.

Example expected output (partial):
```bash
#!/usr/bin/env bash
set -euo pipefail

echo "[dots] Installing packages..."
sudo apt-get update -qq
sudo apt-get install -y \
  zsh \
  git \
  curl \
  tmux \
  neovim \
  ripgrep \
  fzf \
  python3 \
  bat \
  jq
```

- [ ] **Step 3: Run shellcheck on the rendered output**

```bash
chezmoi execute-template < home/run_onchange_install-packages.sh.tmpl | shellcheck -
```

Expected: no output (shellcheck exits 0).

- [ ] **Step 4: Commit**

```bash
git add home/run_onchange_install-packages.sh.tmpl
git commit -m "feat: add run_onchange package install script rendered from packages.yaml"
```

---

## Task 10: `scripts/apply.sh`

**Files:**
- Create: `scripts/apply.sh`

BW-aware apply wrapper. Checks `bw status`, unlocks or logs in as needed, exports `BW_SESSION`, then runs `chezmoi apply`. This is the script `cap()` delegates to.

- [ ] **Step 1: Create `scripts/apply.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# _bw_ensure_session: guarantee BW_SESSION is set and the vault is unlocked.
# ---------------------------------------------------------------------------
_bw_ensure_session() {
    local status
    status=$(bw status 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])" 2>/dev/null || echo "error")

    case "$status" in
        unlocked)
            # BW_SESSION already exported by caller or prior run — nothing to do.
            ;;
        locked)
            echo "[dots] Bitwarden vault is locked. Unlocking..."
            BW_SESSION=$(bw unlock --raw)
            export BW_SESSION
            ;;
        unauthenticated)
            echo "[dots] Not logged in to Bitwarden. Logging in..."
            BW_SESSION=$(bw login --raw)
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
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x scripts/apply.sh
```

- [ ] **Step 3: Run shellcheck**

```bash
shellcheck scripts/apply.sh
```

Expected: no output (exits 0). Fix any warnings before continuing.

- [ ] **Step 4: Commit**

```bash
git add scripts/apply.sh
git commit -m "feat: add BW-aware chezmoi apply wrapper (scripts/apply.sh)"
```

---

## Task 11: `scripts/unmanaged.sh`

**Files:**
- Create: `scripts/unmanaged.sh`

- [ ] **Step 1: Create `scripts/unmanaged.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "[dots] Files in \$HOME not managed by Chezmoi:"
echo "       Review this list periodically and bring configs under management."
echo ""
chezmoi unmanaged
```

- [ ] **Step 2: Make it executable and run shellcheck**

```bash
chmod +x scripts/unmanaged.sh
shellcheck scripts/unmanaged.sh
```

Expected: exits 0.

- [ ] **Step 3: Commit**

```bash
git add scripts/unmanaged.sh
git commit -m "feat: add scripts/unmanaged.sh for periodic state-pruning review"
```

---

## Task 12: `install.sh`

**Files:**
- Create: `install.sh`

Full idempotent bootstrap. Installs chezmoi and `bw` if absent, handles Bitwarden auth, writes per-machine `chezmoi.toml` (interactively or via env vars), then runs `chezmoi init --apply`.

- [ ] **Step 1: Create `install.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

DOTS_REPO="https://github.com/lsztuk/dots"   # update to your actual repo URL

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
info()  { echo "[dots] $*"; }
error() { echo "[dots] ERROR: $*" >&2; exit 1; }

command_exists() { command -v "$1" &>/dev/null; }

# ---------------------------------------------------------------------------
# 1. Detect OS — Ubuntu/apt only for now
# ---------------------------------------------------------------------------
if ! command_exists apt-get; then
    error "Only Ubuntu/apt-based systems are supported. Detected: $(uname -a)"
fi

# ---------------------------------------------------------------------------
# 2. Install chezmoi
# ---------------------------------------------------------------------------
if ! command_exists chezmoi; then
    info "Installing chezmoi..."
    sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
    export PATH="$HOME/.local/bin:$PATH"
fi

# ---------------------------------------------------------------------------
# 3. Install Bitwarden CLI
# ---------------------------------------------------------------------------
if ! command_exists bw; then
    info "Installing Bitwarden CLI..."
    local bw_version="2024.3.1"
    curl -fsSL "https://github.com/bitwarden/clients/releases/download/cli-v${bw_version}/bw-linux-${bw_version}.zip" \
        -o /tmp/bw.zip
    unzip -q /tmp/bw.zip -d /tmp/bw-bin
    install -m 755 /tmp/bw-bin/bw "$HOME/.local/bin/bw"
    rm -rf /tmp/bw.zip /tmp/bw-bin
    export PATH="$HOME/.local/bin:$PATH"
fi

# ---------------------------------------------------------------------------
# 4. Bitwarden auth — always interactive (master password never via env var)
# ---------------------------------------------------------------------------
_bw_ensure_session() {
    local status
    status=$(bw status 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])" 2>/dev/null || echo "error")

    case "$status" in
        unlocked)
            info "Bitwarden vault is already unlocked."
            ;;
        locked)
            info "Bitwarden vault is locked. Unlocking..."
            BW_SESSION=$(bw unlock --raw)
            export BW_SESSION
            ;;
        unauthenticated)
            info "Not logged in to Bitwarden. Logging in..."
            BW_SESSION=$(bw login --raw)
            export BW_SESSION
            ;;
        *)
            error "Could not determine Bitwarden status (got: '$status'). Is bw installed?"
            ;;
    esac
}

_bw_ensure_session

# ---------------------------------------------------------------------------
# 5. Write per-machine chezmoi config (skip if already exists)
# ---------------------------------------------------------------------------
CHEZMOI_CFG="$HOME/.config/chezmoi/chezmoi.toml"

if [ ! -f "$CHEZMOI_CFG" ]; then
    info "Creating per-machine Chezmoi config..."
    mkdir -p "$(dirname "$CHEZMOI_CFG")"

    # Env vars override interactive prompts (headless mode).
    # BW auth (step 4) is always interactive — master password is never an env var.
    machine_role="${MACHINE_ROLE:-}"
    git_name="${GIT_NAME:-}"
    git_email="${GIT_EMAIL:-}"
    proxy="${PROXY:-}"

    if [ -z "$machine_role" ]; then
        read -rp "Machine role (workstation/server/laptop) [workstation]: " machine_role
        machine_role="${machine_role:-workstation}"
    fi

    if [ -z "$git_name" ]; then
        read -rp "Git full name: " git_name
    fi

    if [ -z "$git_email" ]; then
        read -rp "Git email: " git_email
    fi

    if [ -z "$proxy" ]; then
        read -rp "HTTP proxy (leave blank if none): " proxy
    fi

    cat > "$CHEZMOI_CFG" << EOF
[data]
  machineRole = "$machine_role"
  gitName     = "$git_name"
  gitEmail    = "$git_email"
  proxy       = "$proxy"
EOF
    info "Config written to $CHEZMOI_CFG"
else
    info "Chezmoi config already exists at $CHEZMOI_CFG — skipping prompts."
fi

# ---------------------------------------------------------------------------
# 6. Apply dotfiles
# ---------------------------------------------------------------------------
if chezmoi source-path &>/dev/null; then
    info "Chezmoi already initialised — running apply..."
    chezmoi apply
else
    info "Initialising Chezmoi from $DOTS_REPO ..."
    chezmoi init --apply "$DOTS_REPO"
fi

info "Done. Run 'cap' to apply future changes."
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x install.sh
```

- [ ] **Step 3: Run shellcheck**

```bash
shellcheck install.sh
```

Expected: exits 0. Common issue to fix: `local` outside a function — move `bw_version` inside the function or use a global variable.

- [ ] **Step 4: Commit**

```bash
git add install.sh
git commit -m "feat: add idempotent bootstrap install.sh with BW auth and headless mode"
```

---

## Task 13: Gitleaks pre-commit hook

**Files:**
- Create: `.pre-commit-config.yaml`

- [ ] **Step 1: Install `pre-commit` (if not present)**

```bash
pip install pre-commit
```

Verify: `pre-commit --version` → version string.

- [ ] **Step 2: Create `.pre-commit-config.yaml`**

```yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.4
    hooks:
      - id: gitleaks
```

- [ ] **Step 3: Install the hook into this repo**

```bash
pre-commit install
```

Expected:
```
pre-commit installed at .git/hooks/pre-commit
```

- [ ] **Step 4: Run gitleaks against the current repo to verify it passes**

```bash
pre-commit run gitleaks --all-files
```

Expected: `Detect hardcoded secrets...Passed`

- [ ] **Step 5: Commit**

```bash
git add .pre-commit-config.yaml
git commit -m "chore: add gitleaks pre-commit hook for secret leak prevention"
```

---

## Task 14: `scripts/test.sh` — Docker smoke test

**Files:**
- Create: `scripts/test.sh`

This test stubs `bw` (so no real Bitwarden account is needed), writes a test `chezmoi.toml`, runs `chezmoi apply`, and asserts key files exist with correct content.

- [ ] **Step 1: Verify Docker is available**

```bash
docker --version
```

Expected: version string. If absent, install Docker before continuing.

- [ ] **Step 2: Create `scripts/test.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

info()  { echo "[smoke-test] $*"; }
error() { echo "[smoke-test] ERROR: $*" >&2; exit 1; }

info "Building smoke-test Docker image..."

docker build -t dots-smoke-test -f - "$REPO_ROOT" << 'DOCKERFILE'
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -qq && apt-get install -y curl python3 unzip git && rm -rf /var/lib/apt/lists/*

# Install chezmoi
RUN sh -c "$(curl -fsLS get.chezmoi.io)" -- -b /usr/local/bin

# Create test user
RUN useradd -m -s /bin/bash testuser
USER testuser
WORKDIR /home/testuser
DOCKERFILE

info "Running smoke test in container..."

docker run --rm \
    -v "$REPO_ROOT:/dots:ro" \
    dots-smoke-test \
    bash -c '
set -euo pipefail

# --- stub bw ---
mkdir -p ~/bin
cat > ~/bin/bw << '"'"'EOF'"'"'
#!/usr/bin/env bash
case "$1 $2 $3" in
  "status  ")
    echo '"'"'{"status":"unlocked"}'"'"'
    ;;
  "get item dots-git-secrets")
    echo '"'"'{"id":"test","name":"dots-git-secrets","fields":[{"name":"credential_helper","value":"store","type":0}]}'"'"'
    ;;
  *)
    echo "stub bw: unhandled: $*" >&2
    exit 1
    ;;
esac
EOF
chmod +x ~/bin/bw
export PATH=~/bin:$PATH

# --- write test chezmoi config ---
mkdir -p ~/.config/chezmoi
cat > ~/.config/chezmoi/chezmoi.toml << EOF
sourceDir = "/dots/home"

[data]
  machineRole = "workstation"
  gitName     = "Smoke Test User"
  gitEmail    = "smoke@test.com"
  proxy       = ""
EOF

# --- apply (skip run_onchange_ scripts, they need sudo) ---
chezmoi apply --exclude=scripts

# --- assertions ---
assert_file() {
    [ -f "$1" ] || { echo "FAIL: expected file $1"; exit 1; }
    echo "PASS: $1 exists"
}

assert_contains() {
    grep -q "$2" "$1" || { echo "FAIL: $1 does not contain: $2"; exit 1; }
    echo "PASS: $1 contains: $2"
}

assert_file ~/.gitconfig
assert_file ~/.zshrc
assert_file ~/.config/nvim/init.lua
assert_file ~/.config/tmux/tmux.conf

assert_contains ~/.gitconfig "Smoke Test User"
assert_contains ~/.gitconfig "smoke@test.com"
assert_contains ~/.gitconfig "helper = store"
assert_contains ~/.zshrc "cap()"

echo ""
echo "All smoke tests passed."
'

info "Smoke test complete."
```

- [ ] **Step 3: Make it executable**

```bash
chmod +x scripts/test.sh
```

- [ ] **Step 4: Run shellcheck**

```bash
shellcheck scripts/test.sh
```

Expected: exits 0.

- [ ] **Step 5: Run the smoke test**

```bash
scripts/test.sh
```

Expected: all `PASS:` lines and `All smoke tests passed.` at the end. Debug any failures before proceeding.

- [ ] **Step 6: Commit**

```bash
git add scripts/test.sh
git commit -m "test: add Docker smoke test with bw stub and key-file assertions"
```

---

## Task 15: GitHub Actions CI

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Create `.github/workflows/ci.yml`**

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  lint:
    name: Shellcheck + Gitleaks
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Shellcheck
        run: |
          sudo apt-get install -y shellcheck
          find . -name "*.sh" -not -path "./.git/*" | xargs shellcheck

      - name: Gitleaks
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

  smoke-test:
    name: Docker Smoke Test
    runs-on: ubuntu-latest
    needs: lint
    steps:
      - uses: actions/checkout@v4

      - name: Run smoke test
        run: bash scripts/test.sh
```

- [ ] **Step 2: Validate the YAML syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml')); print('OK')"
```

Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add GitHub Actions workflow (shellcheck, gitleaks, smoke test)"
```

---

## Task 16: `README.md`

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Write the README**

```markdown
# dots

Personal dotfiles managed with [Chezmoi](https://chezmoi.io) + Bitwarden.

## Prerequisites

- Ubuntu 22.04+ (other distros: add entries to `packages.yaml`)
- Bitwarden CLI (`bw`) — installed automatically by `install.sh`
- A Bitwarden account with a `dots-git-secrets` item (see Secrets below)

## First-time setup on a new machine

```bash
curl -fsSL https://raw.githubusercontent.com/lsztuk/dots/main/install.sh | bash
```

Or clone first and run locally:
```bash
git clone https://github.com/lsztuk/dots ~/dots
~/dots/install.sh
```

**Headless mode** (for servers / cloud-init):
```bash
MACHINE_ROLE=server GIT_NAME="Lukasz Sztukiewicz" GIT_EMAIL="ops@example.com" ~/dots/install.sh
```
Bitwarden auth remains interactive — master password is never passed as an env var.

## Day-to-day workflow

```bash
# Edit a managed file
chezmoi edit ~/.zshrc

# Preview changes
chezmoi diff

# Apply (BW-aware — handles unlock automatically)
cap

# Commit and push
cdots && git add -A && git commit -m "..." && git push

# Find files not yet managed
~/dots/scripts/unmanaged.sh
```

## Secrets (Bitwarden)

Create the following items in Bitwarden **before** running `install.sh`:

| Item name | Custom fields |
|---|---|
| `dots-git-secrets` | `credential_helper` = `store` (or your preferred helper) |

Add more items as needed. In templates, fetch with:
```
{{- $s := bitwardenFields "item" "item-name" -}}
{{ (index $s "field-name").value }}
```

## Adding packages

Edit `packages.yaml` at the repo root, then run `cap`. The `run_onchange_` script detects the change and re-runs `apt-get install`.

## Structure

```
home/        chezmoi source directory (applied to $HOME)
packages.yaml  package list consumed at template render time
scripts/     helper scripts (never written to $HOME)
install.sh   one-shot bootstrap for a new machine
```
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: write README with setup, workflow, and secrets guide"
```

---

## Self-Review

### Spec coverage check

| Spec section | Covered by task(s) |
|---|---|
| Repository structure | Tasks 1, 3, 4 |
| `exact_` scoping on nvim + tmux | Tasks 7, 8 |
| Per-machine configuration (chezmoi.toml.tmpl) | Task 4 |
| `bitwardenFields` for secrets | Task 5 |
| `fromYaml` + template rendering for packages | Task 9 |
| `install.sh` — idempotent, headless mode | Task 12 |
| `install.sh` — bw status → login/unlock flow | Task 12 |
| `scripts/apply.sh` BW-aware wrapper | Task 10 |
| `cap` shell function in `.zshrc` | Task 6 |
| Gitleaks pre-commit hook | Task 13 |
| `scripts/unmanaged.sh` | Task 11 |
| Docker smoke test | Task 14 |
| GitHub Actions CI | Task 15 |
| README | Task 16 |

All spec requirements are covered.

### Key dependencies between tasks

- Task 9 (`run_onchange_`) requires Task 2 (`packages.yaml`) to exist.
- Task 14 (smoke test) requires Tasks 5–9 to be implemented so the assertions can pass.
- Task 15 (CI) can be written any time but only passes once Task 14 passes.
- Task 16 (README) should be last.

Tasks 1–13 can otherwise proceed in order; no circular dependencies.
