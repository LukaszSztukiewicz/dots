#!/usr/bin/env bash
set -euo pipefail

# Install SDKMAN (Java, Kotlin, Gradle, Maven, etc.). Re-running is safe.
# After install, open a new shell and use `sdk install java <version>` etc.

if [ -d "$HOME/.sdkman" ]; then
    echo "[dots] SDKMAN already installed at $HOME/.sdkman — skipping."
    exit 0
fi

echo "[dots] Installing SDKMAN..."
curl -fsSL https://get.sdkman.io | bash

echo "[dots] SDKMAN installed. Open a new shell to start using it."
