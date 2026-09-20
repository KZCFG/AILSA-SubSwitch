#!/bin/bash
# Native, offscreen renders. The optional JSON accepts reset timestamps only;
# the renderer never opens the account store or initializes live services.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
output="${1:?Usage: render_social.sh OUTPUT [TIMESTAMP_FIXTURE]}"
fixture="${2:-}"
work="$(mktemp -d "${TMPDIR:-/tmp}/ailsa-social.XXXXXX")"
trap 'rm -rf "$work"' EXIT
sources=()
while IFS= read -r file; do sources+=("$file"); done < <(find "$repo/Sources/AILSA_SS" -name '*.swift' | sort)
frameworks=(-framework SwiftUI -framework AppKit -framework WidgetKit -framework Security -framework Combine -framework ServiceManagement -framework Network -framework UniformTypeIdentifiers -lcompression)
xcrun swiftc -emit-library -emit-module -module-name AILSA_SS -enable-testing -DDEBUG \
  -target arm64-apple-macos14.0 -emit-module-path "$work/AILSA_SS.swiftmodule" \
  -o "$work/libAILSA_SS.dylib" "${frameworks[@]}" "${sources[@]}" 2> "$work/build.log" || { cat "$work/build.log"; exit 1; }
bundle="$work/SocialPreview.app/Contents"
mkdir -p "$bundle/MacOS" "$bundle/Resources"
cp -R "$repo"/Sources/AILSA_SS/Resources/*.lproj "$bundle/Resources/"
cp "$repo/Sources/AILSA_SS/Resources/AILSASubSwitch.icns" "$bundle/Resources/"
python3 - "$repo/VERSION" "$bundle/Info.plist" <<'PY'
import sys, plistlib, datetime
version = dict(line.strip().split('=', 1) for line in open(sys.argv[1]) if '=' in line and not line.startswith('#'))
info = dict(CFBundleIdentifier='com.ailsa.social-preview', CFBundleExecutable='render', CFBundlePackageType='APPL',
            CFBundleShortVersionString=version['MARKETING_VERSION'], CFBundleVersion=version['BUILD_NUMBER'],
            ASSBuildLabel=version['BUILD_LABEL'], ASSBuildDate=datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))
with open(sys.argv[2], 'wb') as out: plistlib.dump(info, out)
PY
xcrun swiftc -parse-as-library -target arm64-apple-macos14.0 -I "$work" -L "$work" -lAILSA_SS \
  -Xlinker -rpath -Xlinker "$work" "${frameworks[@]}" \
  "$repo/scripts/render_social.swift" -o "$bundle/MacOS/render"
"$bundle/MacOS/render" "$output" "$fixture"
