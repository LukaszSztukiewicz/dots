#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib/colors.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/colors.sh"

c_info "Files in \$HOME not managed by Chezmoi:"
c_info "      Review this list periodically and bring configs under management."
echo ""
chezmoi unmanaged
