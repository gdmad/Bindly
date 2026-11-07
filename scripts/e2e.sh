#!/bin/bash
# End-to-end run against a separate test build ("BindAll E2E", com.evgeny.bindall.e2e): its own
# settings and data folder, so your BindAll's learned words, history and usage data are untouched.
# Once: grant "BindAll E2E" Accessibility (System Settings -> Privacy & Security -> Accessibility).
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=".build/e2e"
DD=".build/e2e-dd"
APP="$DD/Build/Products/Debug/BindAll E2E.app"
mkdir -p "$OUT"

if pgrep -xq BindAll; then
  echo "Quit BindAll first: two copies would both answer the same keys." >&2
  exit 2
fi

echo "==> Building BindAll E2E"
xcodebuild -scheme BindAll -configuration Debug -derivedDataPath "$DD" \
  PRODUCT_BUNDLE_IDENTIFIER=com.evgeny.bindall.e2e PRODUCT_NAME="BindAll E2E" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Apple Development" PROVISIONING_PROFILE_SPECIFIER="" \
  build -quiet

echo "==> Settings for the test build"
python3 - <<'PY'
import json, subprocess
settings = {
    "enabled": True, "correctEnabled": True, "autocompleteEnabled": True, "autocompleteInline": True,
    "autocompleteLanguages": ["ru"], "languageToolMode": "free", "languageToolLanguage": "ru",
    "proofreadMinLength": 5, "starFieldEnabled": True, "starSelectionEnabled": True,
    "previewFromMenu": True, "defaultEngine": "apple", "historyEnabled": True, "preSendCheck": True,
    "pushToTalkEnabled": True, "pushToTalkLanguage": "ru", "pushToTalkTargetLanguage": "en",
    "sourceLanguage": "ru", "targetLanguage": "en", "restoreClipboard": True,
}
data = json.dumps(settings).encode().hex()
subprocess.run(["defaults", "write", "com.evgeny.bindall.e2e", "BindAll.settings.v1", "-data", data], check=True)
PY
# Push to Talk listens to a recording instead of the microphone.
# Made once and reused while it is a readable audio file: speech synthesis has hung a run before.
VOICE_SECONDS=$(afinfo "$OUT/voice-ru.aiff" 2>/dev/null | awk '/estimated duration/ {print int($3)}')
[ "${VOICE_SECONDS:-0}" -ge 1 ] || say -v Milena "Привет, это проверка голосового ввода" -o "$PWD/$OUT/voice-ru.aiff"
defaults write com.evgeny.bindall.e2e PushToTalkTestAudio "$PWD/$OUT/voice-ru.aiff"
# TextEdit stands in for a chat app for the pre-send check: a Return that gets through is a newline.
defaults write com.evgeny.bindall.e2e PreSendExtraApps -array com.apple.TextEdit
rm -rf "$HOME/Library/Application Support/BindAll E2E/Usage" "$HOME/Library/Application Support/BindAll E2E/history.json"

echo "==> Launching"
pkill -f "BindAll E2E.app" 2>/dev/null || true
for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -f "BindAll E2E.app" >/dev/null || break; sleep 0.5; done
for _ in 1 2 3; do open "$APP" && break; sleep 1; done
sleep 3

echo "==> Driver"
swiftc -O Tests/E2E/*.swift -o "$OUT/driver"
set +e
E2E_ONLY="${E2E_ONLY:-}" "$OUT/driver" "$OUT"
STATUS=$?
set -e

pkill -f "BindAll E2E.app" 2>/dev/null || true
echo "==> Report: $OUT/report.md"
exit $STATUS
