#!/bin/bash
# Render real SwiftUI components using synthetic data; never loads live accounts.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/ass-preview.XXXXXX")"
trap 'rm -rf "$work"' EXIT
sources=()
while IFS= read -r file; do sources+=("$file"); done < <(find "$repo/Sources/Copool" -name '*.swift' | sort)
frameworks=(-framework SwiftUI -framework AppKit -framework WidgetKit -framework Security -framework Combine -framework ServiceManagement -framework Network -framework UniformTypeIdentifiers -lcompression)
xcrun swiftc -emit-library -emit-module -module-name Copool -enable-testing -DDEBUG \
  -target arm64-apple-macos14.0 -emit-module-path "$work/Copool.swiftmodule" \
  -o "$work/libCopool.dylib" "${frameworks[@]}" "${sources[@]}" 2> "$work/build.log" || { cat "$work/build.log"; exit 1; }
cp -R "$repo"/Sources/Copool/Resources/*.lproj "$work/"
xcrun swiftc -parse-as-library -target arm64-apple-macos14.0 -I "$work" -L "$work" -lCopool \
  -Xlinker -rpath -Xlinker "$work" "${frameworks[@]}" \
  "$repo/scripts/render_docs.swift" -o "$work/render"
"$work/render" "$repo/docs/assets"
