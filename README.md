# dots

Personal dotfiles managed with [Chezmoi](https://chezmoi.io) + Bitwarden.

## Prerequisites

- Ubuntu 22.04+
- A Bitwarden account with a `dots-git-secrets` item (see Secrets below)
- Bitwarden CLI and Chezmoi are installed automatically by `install.sh`

## First-time setup on a new machine

```bash
curl -fsSL https://raw.githubusercontent.com/LukaszSztukiewicz/dots/main/install.sh | bash
```

Or clone and run locally:
```bash
git clone https://github.com/lsztuk/dots ~/dots
~/dots/install.sh
```

**Headless mode** (servers / cloud-init — Bitwarden auth remains interactive):
```bash
MACHINE_ROLE=server GIT_NAME="Lukasz Sztukiewicz" GIT_EMAIL="ops@example.com" ~/dots/install.sh
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

Create the following Bitwarden items before running `install.sh`:

| Item name | Custom fields |
|---|---|
| `dots-git-secrets` | `credential_helper` = `store` (or your preferred git credential helper) |

To add more secrets, create a new Bitwarden item and fetch in a template:
```
{{- $s := bitwardenFields "item" "my-item-name" -}}
{{ (index $s "my-field").value }}
```

## Adding packages

Edit `packages.yaml` at the repo root, then run `cap`. The `run_onchange_` script detects the change and re-runs `apt-get install`.

## Repo structure

```
home/           Chezmoi source directory — applied to $HOME
packages.yaml   Package list (consumed at Chezmoi render time, not by shell)
scripts/        Helper scripts — never written to $HOME
install.sh      One-shot bootstrap for a new machine
```
