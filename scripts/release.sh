#!/usr/bin/env bash
# Buduje macOS i Android i tworzy wydanie na GitHubie. Uruchom na Macu z repo.
# Uzycie: scripts/release.sh            (wersja z app/pubspec.yaml)
# Nazwy plikow zawieraja "macos" i "android", bo po tym UpdateChecker wybiera plik.
# z pomocą AI (Claude)
set -euo pipefail
cd "$(dirname "$0")/../app"

VER=$(grep '^version:' pubspec.yaml | sed 's/version: *//; s/+.*//')
TAG="v$VER"
OUT=../build-release
rm -rf "$OUT"; mkdir -p "$OUT"

command -v gh >/dev/null || { echo "brak gh (brew install gh && gh auth login)"; exit 1; }
if [ -n "$(git status --porcelain -- .)" ]; then
  echo "niezacommitowane zmiany w app/, zacommituj i wypchnij przed wydaniem"; exit 1
fi
git fetch -q origin
if [ "$(git rev-parse HEAD)" != "$(git rev-parse @{u})" ]; then
  echo "HEAD rozni sie od origin, zrob git push"; exit 1
fi

flutter pub get
flutter build macos --release
ditto -c -k --sequesterRsrc --keepParent \
  build/macos/Build/Products/Release/*.app "$OUT/neurotchi-$VER-macos.zip"

flutter build apk --release
cp build/app/outputs/flutter-apk/app-release.apk "$OUT/neurotchi-$VER-android.apk"

gh release create "$TAG" "$OUT"/* --title "NEUROtchi $VER" \
  --notes "Wydanie $VER. macOS: rozpakuj, prawy klik, Otwórz (aplikacja niepodpisana). Android: zainstaluj APK."
echo "gotowe: $TAG"
