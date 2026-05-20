#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib/colors.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/colors.sh"

# Install uv (fast Python package + project manager from Astral). Re-runnable.
# After install, open a new shell — .zshrc sources ~/.local/bin/env which uv drops there.

c_step "Installing uv..."
curl -fsSL https://astral.sh/uv/install.sh | sh

c_ok "uv installed. Open a new shell or run: . \"\$HOME/.local/bin/env\""
