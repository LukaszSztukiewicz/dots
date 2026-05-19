#!/usr/bin/env bash
set -euo pipefail

# Install juliaup (Julia version manager). Re-running re-applies the upstream
# installer, which is idempotent.
# After install, open a new shell and run `julia` (juliaup auto-installs the
# default Julia channel on first call) or `juliaup add release`.

echo "[dots] Installing juliaup..."
# -y skips the interactive shell-config writeback; .zshrc already prepends
# ~/.juliaup/bin guarded by an existence check.
curl -fsSL https://install.julialang.org | sh -s -- --yes

echo "[dots] juliaup installed. Open a new shell to use it."
