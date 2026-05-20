# dots

Personal dotfiles managed with [Chezmoi](https://chezmoi.io) + Bitwarden.

## Prerequisites

- Ubuntu 22.04+
- A Bitwarden account with a `dots-git-secrets` item (see Secrets below)
- Bitwarden CLI and Chezmoi are installed automatically by `bootstrap.sh`

## First-time setup on a new machine

```bash
curl -fsSL https://raw.githubusercontent.com/LukaszSztukiewicz/dots/main/bootstrap.sh | bash
```

The script installs `bw` + `chezmoi`, authenticates with Bitwarden, prompts
for `MACHINE_ROLE`, git name/email, and proxy, then clones and applies the
dotfiles. If you've already cloned the repo you can run it locally:

```bash
~/dots/bootstrap.sh
```

**Headless mode** (servers / cloud-init / CI — no TTY at all):

Set every value the script would otherwise prompt for via env vars.
Bitwarden needs an [API key](https://bitwarden.com/help/personal-api-key/)
for login and the master password for unlock:

```bash
export BW_CLIENTID="user.xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export BW_CLIENTSECRET="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
export BW_PASSWORD="<vault master password>"
export MACHINE_ROLE=remote
export GIT_NAME="Lukasz Sztukiewicz"
export GIT_EMAIL="ops@example.com"

curl -fsSL https://raw.githubusercontent.com/LukaszSztukiewicz/dots/main/bootstrap.sh | bash
```

If `BW_CLIENTID`/`BW_CLIENTSECRET` (or `BW_PASSWORD`) are missing **and** no
TTY is available, `bootstrap.sh` aborts with an explicit message rather
than hanging.

**Re-run without re-authing** — if you already have a valid session, export it
before running and the Bitwarden auth step is skipped:

```bash
export BW_SESSION='...'
~/dots/bootstrap.sh
```

**Full reproduction / re-bootstrap** — set `DOTS_RESET=1` on `bootstrap.sh`
to wipe install-side state (Chezmoi config, cloned source dir, `bw` binary
and session, local `chezmoi` binary) before continuing. Applied dotfiles
in `$HOME` are not touched.

**Decommission / security wipe** — set `DOTS_NUKE=1` on `bootstrap.sh` to
additionally remove applied dotfiles, Oh My Zsh, fzf, language toolchains,
the p10k cache, shell history, and the bash→zsh trampoline. Prompts for a
typed `NUKE` confirmation unless `DOTS_NUKE_FORCE=1` is also set. Both
modes shell out to `scripts/cleanup.sh`, which can also be invoked
directly: `~/dots/scripts/cleanup.sh --nuke [--force]`.

The env var has to apply to `bash` (not to `curl`), so put it on the right
side of the pipe:

```bash
curl -fsSL https://raw.githubusercontent.com/LukaszSztukiewicz/dots/main/bootstrap.sh | DOTS_RESET=1 bash
```

## Day-to-day workflow

```bash
chezmoi edit ~/.zshrc   # edit a managed file
chezmoi diff            # preview what apply would change
cap                     # BW-aware apply (handles unlock automatically)
cdots && git add -A && git commit -m "..." && git push
~/dots/scripts/unmanaged.sh   # list files not yet managed
```

## Secrets (Bitwarden)

Create the following Bitwarden items before running `bootstrap.sh`:

| Item name | Custom fields |
|---|---|
| `dots-git-secrets` | `credential_helper` = `store` (or your preferred git credential helper) |

To add more secrets, create a new Bitwarden item and fetch in a template:
```
{{- $s := bitwardenFields "item" "my-item-name" -}}
{{ (index $s "my-field").value }}
```

```bash
# session is still set from your last bootstrap.sh run; export it again if needed
apt-get install -y jq

bw get template item \
| jq '.name="dots-git-secrets"
        | .type=2
        | .secureNote={"type":0}
        | .fields=[{"name":"credential_helper","value":"store","type":0,"linkedId":null}]' \
| bw encode \
| bw create item
```

## Adding packages

Edit `packages.yaml` at the repo root, then run `cap`. The `run_onchange_` script detects the change and re-runs `apt-get install`.

## Optional on-demand installs

Install only when needed; each script drops the tool into `~/.local/bin` (or a
tool-specific dir) without touching `.zshrc` — init blocks in `.zshrc` are
already there, gated on existence checks.

Both forms work — repo-local if you cloned, or one-shot via `curl | bash`
if you didn't:

```bash
# repo-local
~/dots/scripts/install-tmux.sh

# no clone needed
curl -fsSL https://raw.githubusercontent.com/LukaszSztukiewicz/dots/main/scripts/install-tmux.sh | bash
```

| Tool | Install command | Purpose |
|---|---|---|
| **uv** | `~/dots/scripts/install-uv.sh` | Fast Python package / project manager (Astral) |
| **nvm** | `~/dots/scripts/install-nvm.sh` | Node version manager |
| **juliaup** | `~/dots/scripts/install-juliaup.sh` | Julia version manager |
| **conda** | `~/dots/scripts/install-conda.sh` | Miniconda into `~/miniconda3` |
| **sdkman** | `~/dots/scripts/install-sdkman.sh` | JVM toolchain manager (Java/Kotlin/Gradle/...) |
| **tmux** (static) | `~/dots/scripts/install-tmux.sh` | tmux ≥ 3.3 for OSC52 nested-clipboard passthrough on systems where apt's tmux is too old. No sudo needed; shadows `/usr/bin/tmux` via `~/.local/bin`. |

After running one, open a new shell.

Override versions/paths with env vars:
- `NVM_VERSION=v0.40.0 ~/dots/scripts/install-nvm.sh`
- `CONDA_PREFIX_DIR=/opt/miniconda ~/dots/scripts/install-conda.sh`
- `TMUX_VERSION=3.5a ~/dots/scripts/install-tmux.sh`

## Per-machine setup (one-time)

After the first `chezmoi apply` on a new machine:

- **Powerlevel10k prompt** — `~/.p10k.zsh` is tracked by chezmoi
  (`home/dot_p10k.zsh.tmpl`). It contains a Chezmoi-templated role-accent
  override at the very end (`local` = cyan context segment, `remote` /
  `agent` = default amber). If you re-run `p10k configure` and want to keep
  your tweaks, copy the regenerated file back into the source dir and re-add
  the role block.

### Machine roles

`MACHINE_ROLE` (env var or `.chezmoi.toml`) is one of:

| Role | Meaning |
|---|---|
| `remote` | Default. Full install — your workstation/dev box. Amber p10k accent. |
| `local`  | Same install as remote, plus a cyan p10k/tmux accent so you can tell it apart at a glance. Use for laptops or anywhere you want the visual distinction. |
| `agent`  | Same install as remote. Label is metadata only — useful as a "this is a Claude-Code/CI sandbox" marker. |
- **sudoedit honors $EDITOR** — add `Defaults env_editor` via `sudo visudo` if
  you want `sudoedit` to follow the `EDITOR=vim` env var instead of the
  alternatives default.

## Repo structure

```
home/           Chezmoi source directory — applied to $HOME
packages.yaml   Package list (consumed at Chezmoi render time, not by shell)
scripts/        Helper scripts — never written to $HOME
bootstrap.sh    One-shot bootstrap for a new machine
```

## Troubleshooting
You have two vault items named dots-git-secrets — bw get item <name> only works when the name is unique. Inspect both, keep the one you want, delete the other.

```
 bw get item <id> | jq '{name, fields}'
 bw delete item <id>
```