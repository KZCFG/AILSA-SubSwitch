#!/bin/bash
# Render real SwiftUI components using synthetic data; never loads live accounts.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/ass-preview.XXXXXX")"
trap 'rm -rf "$work"' EXIT
sources=()
while IFS= read -r file; do sources+=("$file"); done < <(find "$repo/Sources/AILSA_SS" -name '*.swift' | sort)
frameworks=(-framework SwiftUI -framework AppKit -framework WidgetKit -framework Security -framework Combine -framework ServiceManagement -framework Network -framework UniformTypeIdentifiers -lcompression)
xcrun swiftc -emit-library -emit-module -module-name AILSA_SS -enable-testing -DDEBUG \
  -target arm64-apple-macos14.0 -emit-module-path "$work/AILSA_SS.swiftmodule" \
  -o "$work/libAILSA_SS.dylib" "${frameworks[@]}" "${sources[@]}" 2> "$work/build.log" || { cat "$work/build.log"; exit 1; }
cp -R "$repo"/Sources/AILSA_SS/Resources/*.lproj "$work/"
xcrun swiftc -parse-as-library -target arm64-apple-macos14.0 -I "$work" -L "$work" -lAILSA_SS \
  -Xlinker -rpath -Xlinker "$work" "${frameworks[@]}" \
  "$repo/scripts/render_docs.swift" -o "$work/render"
"$work/render" "$repo/docs/assets"
if [[ "${1:-}" == "--account-smoke" ]]; then
  xcrun swiftc -parse-as-library -target arm64-apple-macos14.0 -I "$work" -L "$work" -lAILSA_SS \
    -Xlinker -rpath -Xlinker "$work" "${frameworks[@]}" \
    "$repo/scripts/testing/AccountGridSmoke.swift" -o "$work/account-grid-smoke"
  "$work/account-grid-smoke"
fi
