#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib/colors.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/colors.sh"

# Install juliaup (Julia version manager). Re-running re-applies the upstream
# installer, which is idempotent.
# After install, open a new shell and run `julia` (juliaup auto-installs the
# default Julia channel on first call) or `juliaup add release`.

c_step "Installing juliaup..."
# -y skips the interactive shell-config writeback; .zshrc already prepends
# ~/.juliaup/bin guarded by an existence check.
curl -fsSL https://install.julialang.org | sh -s -- --yes

c_ok "juliaup installed. Open a new shell to use it."
