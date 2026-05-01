#!/usr/bin/env bash
set -euo pipefail

echo "[dots] Files in \$HOME not managed by Chezmoi:"
echo "       Review this list periodically and bring configs under management."
echo ""
chezmoi unmanaged
