#!/usr/bin/env bash
set -euo pipefail

# Install uv (fast Python package + project manager from Astral). Re-runnable.
# After install, open a new shell — .zshrc sources ~/.local/bin/env which uv drops there.

echo "[dots] Installing uv..."
curl -fsSL https://astral.sh/uv/install.sh | sh

echo "[dots] uv installed. Open a new shell or run: . \"\$HOME/.local/bin/env\""
