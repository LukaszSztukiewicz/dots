#!/usr/bin/env bash
set -euo pipefail

# Install Node Version Manager. Re-running is safe (upstream script is idempotent).
# After install, open a new shell or `source ~/.zshrc` to pick up nvm.

NVM_VERSION="${NVM_VERSION:-v0.39.7}"

echo "[dots] Installing nvm ${NVM_VERSION}..."
curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash

echo "[dots] nvm installed. Open a new shell and run 'nvm install --lts' to get Node."
