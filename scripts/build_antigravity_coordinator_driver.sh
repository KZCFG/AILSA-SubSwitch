#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_path="${1:-/tmp/ailsa-antigravity-coordinator-driver}"

# Link the complete production module, including the application delegate used
# by the quota window. Dropping AILSA_SSApp.swift leaves that symbol unavailable.
# As in the CLT test runner, importing the library does not run the GUI @main.
support_dir="${output_path}.support"
mkdir -p "$(dirname "$output_path")" "$support_dir"
source_files=()
while IFS= read -r file; do source_files+=("$file"); done < <(find "$repo_dir/Sources/AILSA_SS" -name '*.swift' -print | sort)
frameworks=(-framework SwiftUI -framework AppKit -framework WidgetKit -framework Security -framework Combine -framework ServiceManagement -framework Network -framework UniformTypeIdentifiers -lcompression)

# Keep this command intentionally aligned with the independently verified
# candidate build: arm64 macOS 14, and libcompression rather than a nonexistent
# Compression framework linker target.
xcrun --sdk macosx swiftc \
  -target arm64-apple-macos14.0 \
  -O -emit-library -emit-module -module-name AILSA_SS -enable-testing \
  -emit-module-path "$support_dir/AILSA_SS.swiftmodule" \
  -o "$support_dir/libAILSA_SS.dylib" \
  "${source_files[@]}" "${frameworks[@]}"

xcrun --sdk macosx swiftc \
  -target arm64-apple-macos14.0 -parse-as-library -O \
  -I "$support_dir" -L "$support_dir" -lAILSA_SS \
  -Xlinker -rpath -Xlinker "$support_dir" \
  -o "$output_path" "$repo_dir/scripts/antigravity_coordinator_driver.swift" \
  "${frameworks[@]}"

echo "$output_path"
