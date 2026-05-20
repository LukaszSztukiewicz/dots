#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib/colors.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/colors.sh"

# Install SDKMAN (Java, Kotlin, Gradle, Maven, etc.). Re-running is safe.
# After install, open a new shell and use `sdk install java <version>` etc.

if [ -d "$HOME/.sdkman" ]; then
    c_info "SDKMAN already installed at $HOME/.sdkman — skipping."
    exit 0
fi

c_step "Installing SDKMAN..."
curl -fsSL https://get.sdkman.io | bash

c_ok "SDKMAN installed. Open a new shell to start using it."
