#!/usr/bin/env bash
# Sparkle's EdDSA key pair: made once, kept in the login keychain; prints the
# public key (which goes in every release build). `-p` prints it only.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
"$(sparkle_tool generate_keys)" --account "$SPARKLE_KEY_ACCOUNT" "$@"
