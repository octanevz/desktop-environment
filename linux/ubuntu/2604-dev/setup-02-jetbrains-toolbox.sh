#!/bin/bash
set -euo pipefail

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
setup_begin "$@"

# Nothing between here and the end leaves the machine untouched - it runs the Toolbox installer
# straight away - so the completion marker goes now.
setup_invalidate

# Install JetBrains Toolbox
curl -fsSL https://raw.githubusercontent.com/nagygergo/jetbrains-toolbox-install/4184247d1d12888024181f27dea7b7868d8f9e81/jetbrains-toolbox.sh | bash

setup_end
