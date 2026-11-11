#!/bin/zsh
# Builds Local Mind and packs it into a DMG with an Applications shortcut, for your own Macs.
# It's signed with your development certificate, not notarized, so it's not for sharing.
# Usage: tools/make_dmg.sh            writes dist/Local Mind.dmg
set -euo pipefail
here=${0:A:h:h}
"$here/build.sh" >/dev/null
app="$HOME/Applications/Local Mind.app"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/Local Mind.app"
ln -s /Applications "$stage/Applications"
mkdir -p "$here/dist"
out="$here/dist/Local Mind.dmg"
rm -f "$out"
hdiutil create -volname "Local Mind" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$out" >/dev/null
echo "wrote $out ($(du -h "$out" | cut -f1))"
