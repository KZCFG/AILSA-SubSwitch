#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_path="${1:-/tmp/ailsa-antigravity-coordinator-driver}"

# CopoolApp.swift supplies the GUI application's @main. The driver supplies a
# separate @main while linking the same production implementation files.
source_files=$(find "$repo_dir/Sources/Copool" -name '*.swift' ! -name 'CopoolApp.swift' -print | sort)

# Keep this command intentionally aligned with the independently verified
# candidate build: arm64 macOS 14, and libcompression rather than a nonexistent
# Compression framework linker target.
xcrun --sdk macosx swiftc \
  -target arm64-apple-macos14.0 \
  -O \
  -o "$output_path" \
  $source_files \
  "$repo_dir/scripts/antigravity_coordinator_driver.swift" \
  -framework SwiftUI \
  -framework AppKit \
  -framework WidgetKit \
  -framework Security \
  -framework Combine \
  -lcompression

echo "$output_path"
