#!/bin/zsh
# Buduje QuakeLauncher.app i QuakeConfig.app — wymaga tylko Command Line Tools (swiftc).
#   ./build.sh        — buduje i podpisuje obie aplikacje
#   ./build.sh dist   — dodatkowo składa QuakeTools.dmg; jeśli podpis to Developer ID
#                       i istnieje profil notarytool (NOTARY_PROFILE, domyślnie
#                       "quaketools"), DMG jest notaryzowany i staplowany.
# Tożsamość podpisu można nadpisać: SIGN_ID="..." ./build.sh
set -e
cd "$(dirname "$0")"

NOTARY_PROFILE="${NOTARY_PROFILE:-quaketools}"

# preferuj Developer ID > Apple Development > ad-hoc (pierwsza pasująca tożsamość z pęku kluczy)
if [[ -z "$SIGN_ID" ]]; then
  for kind in "Developer ID Application" "Apple Development"; do
    SIGN_ID=$(security find-identity -v -p codesigning | grep -oE "\"$kind: [^\"]*\"" | head -1 | tr -d '"')
    [[ -n "$SIGN_ID" ]] && break
  done
fi
SIGN_ID="${SIGN_ID:--}"

# hardened runtime + znacznik czasu są wymagane do notaryzacji (nie działają z ad-hoc)
SIGN_FLAGS=()
[[ "$SIGN_ID" != "-" ]] && SIGN_FLAGS=(--options runtime --timestamp)

# Minimalny system. Bez -target swiftc bierze wersję hosta, więc binarka dostawała
# minos równy aktualnemu macOS — niezależnie od tego, co deklarował Info.plist.
DEPLOY_TARGET="${DEPLOY_TARGET:-15.0}"

# build_app <exe> — źródła z Sources/<exe>/, Info.plist i ikona z Resources/<exe>/
build_app() {
  local exe=$1
  local app="$exe.app"
  swiftc -O -parse-as-library -target "$(uname -m)-apple-macos$DEPLOY_TARGET" Sources/$exe/**/*.swift -o "$exe"
  rm -rf "$app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  cp "Resources/$exe/Info.plist" "$app/Contents/Info.plist"
  cp "Resources/$exe/$exe.icns" "$app/Contents/Resources/"
  mv "$exe" "$app/Contents/MacOS/"
}

build_app QuakeLauncher
build_app QuakeConfig

# shim wyboru monitora — uniwersalny, bo QuakeSpasm to x86_64 (Rosetta)
clang -arch arm64 -arch x86_64 -dynamiclib -undefined dynamic_lookup -O2 \
  -mmacosx-version-min=$DEPLOY_TARGET \
  Sources/DisplayShim/displayshim.c -o QuakeLauncher.app/Contents/Resources/libdisplayshim.dylib

codesign --force --sign "$SIGN_ID" "${SIGN_FLAGS[@]}" QuakeLauncher.app/Contents/Resources/libdisplayshim.dylib
codesign --force --sign "$SIGN_ID" "${SIGN_FLAGS[@]}" QuakeLauncher.app
codesign --force --sign "$SIGN_ID" "${SIGN_FLAGS[@]}" QuakeConfig.app
echo "Gotowe (podpis: $SIGN_ID): QuakeLauncher.app, QuakeConfig.app"

if [[ "$1" == "dist" ]]; then
  VOLNAME="Quake Tools"

  # tło okna (1x + 2x → TIFF Retina)
  BGDIR=$(mktemp -d)
  swift Tools/dmgbg.swift "$BGDIR" >/dev/null
  tiffutil -cathidpicheck "$BGDIR/background.png" "$BGDIR/background@2x.png" \
    -out "$BGDIR/background.tiff" 2>/dev/null

  STAGE=$(mktemp -d)
  cp -R QuakeLauncher.app QuakeConfig.app "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  mkdir "$STAGE/.background"
  cp "$BGDIR/background.tiff" "$STAGE/.background/"
  cp Resources/QuakeLauncher/QuakeLauncher.icns "$STAGE/.VolumeIcon.icns"
  rm -rf "$BGDIR"

  # najpierw obraz RW: Finder ustawia w nim układ okna, potem konwersja do UDZO
  rm -f QuakeTools.dmg tmp-rw.dmg
  # odmontuj wiszące woluminy o tej nazwie — AppleScript celuje po nazwie dysku
  for vol in /Volumes/"$VOLNAME"*(N); do
    [[ -d "$vol" ]] && hdiutil detach "$vol" -quiet 2>/dev/null
  done
  hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -format UDRW -quiet -o tmp-rw.dmg
  rm -rf "$STAGE"
  MOUNT=$(hdiutil attach tmp-rw.dmg -readwrite -noverify -noautoopen | awk -F'\t' '/\/Volumes\//{print $NF; exit}')
  DISKNAME=$(basename "$MOUNT")
  # flaga "custom icon" na korzeniu woluminu (FinderInfo, bit 0x0400)
  xattr -wx com.apple.FinderInfo \
    "0000000000000000040000000000000000000000000000000000000000000000" "$MOUNT"

  osascript <<OSA
tell application "Finder"
  tell disk "$DISKNAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 140, 860, 580}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 100
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "QuakeLauncher.app" of container window to {160, 130}
    set position of item "QuakeConfig.app" of container window to {160, 315}
    set position of item "Applications" of container window to {505, 222}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA

  sync; sleep 2
  hdiutil detach "$MOUNT" -quiet || { sleep 3; hdiutil detach "$MOUNT" -force -quiet; }
  hdiutil convert tmp-rw.dmg -format UDZO -quiet -o QuakeTools.dmg
  rm -f tmp-rw.dmg
  codesign --force --sign "$SIGN_ID" QuakeTools.dmg 2>/dev/null || true
  echo "Gotowe: QuakeTools.dmg"

  if [[ "$SIGN_ID" == Developer\ ID* ]]; then
    echo "Wysyłam do notaryzacji (profil: $NOTARY_PROFILE)…"
    SUB_ID=$(xcrun notarytool submit QuakeTools.dmg --keychain-profile "$NOTARY_PROFILE" 2>&1 | awk '/^  id:/{print $2; exit}')
    [[ -z "$SUB_ID" ]] && { echo "⚠︎ submit nie zwrócił id submisji"; exit 1; }
    echo "Submisja: $SUB_ID — czekam na werdykt Apple…"
    while true; do
      STATUS=$(xcrun notarytool info "$SUB_ID" --keychain-profile "$NOTARY_PROFILE" 2>/dev/null | awk '/status:/{sub(/^ *status: */,""); print; exit}')
      echo "  $(date +%H:%M:%S) status: ${STATUS:-(brak odpowiedzi)}"
      case "$STATUS" in
        Accepted)
          xcrun stapler staple QuakeTools.dmg
          echo "Notaryzacja + stapling OK — DMG gotowy do dystrybucji."
          break;;
        Invalid|Rejected)
          echo "⚠︎ Notaryzacja odrzucona — log:"
          xcrun notarytool log "$SUB_ID" --keychain-profile "$NOTARY_PROFILE"
          exit 1;;
      esac
      sleep 60
    done
  fi
fi
