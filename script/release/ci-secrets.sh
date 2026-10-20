#!/usr/bin/env bash
# Puts what the GitHub Actions release needs (.github/workflows/release.yml)
# in this repository's `release` environment, once; again to replace one.
# Read from files and hidden prompts, sent with gh, never printed or kept.
#
#   script/release/ci-secrets.sh <Developer ID .p12> <AuthKey_XXXXXXXXXX.p8>
#
# The .p12: Keychain Access → My Certificates → "Developer ID Application:
# NOM DE LA SOCIETE" → Export…, with a password. The .p8: App Store Connect →
# Users and Access → Integrations → Team Keys → a key with the Developer role
# (downloadable once; its ID is in the file's name). Sparkle's key is taken
# from this Mac's login keychain (macOS may ask to allow it once).
# SKILLI_KLIPY_KEY is already there; `--klipy` asks for it again.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$ROOT_DIR"

klipy=0
args=()
for arg in "$@"; do
  if [[ "$arg" == --klipy ]]; then klipy=1; else args+=("$arg"); fi
done
[[ ${#args[@]} -eq 2 && -f "${args[0]}" && -f "${args[1]}" ]] || {
  echo "Usage: script/release/ci-secrets.sh <Developer ID .p12> <AuthKey_XXXXXXXXXX.p8> [--klipy]" >&2
  exit 2
}
p12="${args[0]}"
p8="${args[1]}"
key_id="$(basename "$p8" .p8)"
key_id="${key_id#AuthKey_}"
[[ "$key_id" =~ ^[A-Z0-9]{10}$ ]] || { echo "“$(basename "$p8")” is not named AuthKey_<10-character ID>.p8: keep Apple's file name." >&2; exit 2; }
target=(--env release --repo "$RELEASES_REPO")

# The certificate and its password: checked together before anything is sent.
read -rsp "Password of $(basename "$p12"): " p12_password
echo
openssl pkcs12 -in "$p12" -passin "pass:$p12_password" -nokeys -legacy 2>/dev/null | grep -q "Developer ID Application" \
  || openssl pkcs12 -in "$p12" -passin "pass:$p12_password" -nokeys 2>/dev/null | grep -q "Developer ID Application" \
  || { echo "That .p12 does not open with this password, or holds no Developer ID Application certificate." >&2; exit 2; }
base64 -i "$p12" | gh secret set DEVELOPER_ID_P12 "${target[@]}"
printf '%s' "$p12_password" | gh secret set DEVELOPER_ID_P12_PASSWORD "${target[@]}"

# Notarization: the API key, its ID (from the file's name) and the team's issuer.
gh secret set NOTARY_API_KEY "${target[@]}" < "$p8"
gh variable set NOTARY_KEY_ID "${target[@]}" --body "$key_id"
read -rp "App Store Connect issuer ID (above the keys' list): " issuer
[[ "$issuer" =~ ^[0-9a-f-]{36}$ ]] || { echo "An issuer ID looks like 57246542-96fe-1a63-e053-0824d011072a." >&2; exit 2; }
gh variable set NOTARY_ISSUER_ID "${target[@]}" --body "$issuer"

# Sparkle: the private key out of the login keychain into a file only this
# script reads, sent, removed; the public key as a plain variable.
sparkle="$(mktemp)"
trap 'rm -f "$sparkle"' EXIT
rm -f "$sparkle"
"$(sparkle_tool generate_keys)" --account "$SPARKLE_KEY_ACCOUNT" -x "$sparkle" >/dev/null
gh secret set SPARKLE_ED_PRIVATE_KEY "${target[@]}" < "$sparkle"
rm -f "$sparkle"
gh variable set SKILLI_SPARKLE_PUBLIC_ED_KEY "${target[@]}" --body "$("$(sparkle_tool generate_keys)" --account "$SPARKLE_KEY_ACCOUNT" -p)"

# The Homebrew tap: a fine-grained token for nomdelasociete/homebrew-tap only,
# Contents read and write (github.com/settings/personal-access-tokens).
read -rsp "Token for $TAP_REPO (Contents: read and write): " tap
echo
[[ -n "$tap" ]] && printf '%s' "$tap" | gh secret set HOMEBREW_TAP_TOKEN "${target[@]}"

if [[ "$klipy" == 1 ]]; then
  read -rsp "skil.li's Klipy key: " klipy_key
  echo
  printf '%s' "$klipy_key" | gh secret set SKILLI_KLIPY_KEY "${target[@]}"
fi

echo "The release environment now holds:"
gh secret list "${target[@]}"
gh variable list "${target[@]}"
