#!/bin/bash
# Regenerate the macOS icon from the same artwork used by the project page.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
source_icon="$repo/docs/assets/app-icon.png"
work="$(mktemp -d "${TMPDIR:-/tmp}/ass-icon.XXXXXX")"
trap 'rm -rf "$work"' EXIT
iconset="$work/AILSASubSwitch.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$source_icon" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  retina_size=$((size * 2))
  sips -z "$retina_size" "$retina_size" "$source_icon" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$work/AILSASubSwitch.icns"
cp "$work/AILSASubSwitch.icns" "$repo/Sources/Copool/Resources/AILSASubSwitch.icns"
printf 'Updated AILSASubSwitch.icns from docs/assets/app-icon.png\n'
