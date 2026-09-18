#!/bin/bash
set -euo pipefail

# Single-command, source-only build of AILSA SubSwitch.app (+ widget appex) and
# a distributable zip.
#
#   scripts/build_app.sh                 # ad-hoc signed, output under build/
#   scripts/build_app.sh --output DIR    # explicit output directory (must not exist)
#   scripts/build_app.sh --skip-zip      # bundle only
#   scripts/build_app.sh --no-sign       # compile + bundle, no codesign (smoke builds)
#   CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/build_app.sh
#
# Guarantees:
#   * Compiles every Swift source in Sources/ with `xcrun swiftc`; needs only the
#     Command Line Tools (no Xcode.app, no SwiftPM, no actool).
#   * Never copies from /Applications, never reads previously built binaries.
#   * Version, build number and build label come from the repo-root VERSION file.
#   * No personal signing identity is baked in. Default is ad-hoc ("-").
#   * Source paths are remapped (-file-prefix-map) so the binary does not embed
#     the builder's home directory.

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"

output_root=""
skip_zip=0
do_sign=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) output_root="$2"; shift 2 ;;
    --skip-zip) skip_zip=1; shift ;;
    --no-sign) do_sign=0; shift ;;
    -h|--help) sed -n '3,22p' "$0"; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------
# Version (single source of truth)
# ---------------------------------------------------------------------------
version_file="$repo_dir/VERSION"
[[ -f "$version_file" ]] || { printf 'Missing %s\n' "$version_file" >&2; exit 2; }
read_version_key() {
  local value
  value="$(sed -n "s/^$1=//p" "$version_file" | head -n1)"
  [[ -n "$value" ]] || { printf 'VERSION lacks %s\n' "$1" >&2; exit 2; }
  printf '%s' "$value"
}
marketing_version="$(read_version_key MARKETING_VERSION)"
build_number="$(read_version_key BUILD_NUMBER)"
build_label="$(read_version_key BUILD_LABEL)"

# Bundle identity is intentionally unchanged so existing account data and
# keychain items keep working. Override only if you know what you are doing.
app_bundle_id="${APP_BUNDLE_ID:-com.ailsa.subswitch}"
widget_bundle_id="${WIDGET_BUNDLE_ID:-com.ailsa.subswitch.widgets}"
app_display_name="AILSA SubSwitch"
codesign_identity="${CODESIGN_IDENTITY:--}"
target_triple="${SWIFT_TARGET:-arm64-apple-macos14.0}"

build_date="$(python3 -c 'import os,datetime; print(datetime.datetime.fromtimestamp(int(os.environ["SOURCE_DATE_EPOCH"]),datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ") if "SOURCE_DATE_EPOCH" in os.environ else datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))')"

if [[ -z "$output_root" ]]; then
  output_root="$repo_dir/build/${build_label}-${build_number}"
fi
if [[ -e "$output_root" ]]; then
  printf 'Refusing to overwrite existing output: %s\n' "$output_root" >&2
  exit 2
fi

app_bundle="$output_root/$app_display_name.app"
app_contents="$app_bundle/Contents"
app_binary="$app_contents/MacOS/AILSA_SS"
app_resources="$app_contents/Resources"
widget_bundle="$app_contents/PlugIns/AILSA_SSWidgetsMac.appex"
widget_contents="$widget_bundle/Contents"
widget_binary="$widget_contents/MacOS/AILSA_SSWidgetsMac"

mkdir -p "$app_contents/MacOS" "$app_resources" "$widget_contents/MacOS"

# ---------------------------------------------------------------------------
# Compile
# ---------------------------------------------------------------------------
app_sources=()
while IFS= read -r source_file; do
  app_sources+=("$source_file")
done < <(find "$repo_dir/Sources/AILSA_SS" -type f -name '*.swift' -print | sort)

common_swift_flags=(
  -target "$target_triple"
  -O
  -file-prefix-map "$repo_dir=/AILSA-SubSwitch"
  -framework SwiftUI
  -framework AppKit
  -framework WidgetKit
  -framework Security
  -framework Combine
  -framework ServiceManagement
  -framework Network
  -framework UniformTypeIdentifiers
  -lcompression
)

printf '[build_app] compiling app (%d sources)\n' "${#app_sources[@]}"
xcrun --sdk macosx swiftc \
  "${common_swift_flags[@]}" \
  -module-name AILSA_SS \
  -o "$app_binary" \
  "${app_sources[@]}"

# The widget links a small, explicit subset of app files. Keep this list in
# sync with Sources/AILSA_SSWidgets/*.swift imports.
widget_sources=(
  "$repo_dir/Sources/AILSA_SSWidgets/AILSA_SSWidgets.swift"
  "$repo_dir/Sources/AILSA_SSWidgets/AccountsWidgetViews.swift"
  "$repo_dir/Sources/AILSA_SS/WidgetSupport/AccountsWidgetSnapshot.swift"
  "$repo_dir/Sources/AILSA_SS/WidgetSupport/AccountsWidgetSnapshotStore.swift"
  "$repo_dir/Sources/AILSA_SS/Domain/AppError.swift"
  "$repo_dir/Sources/AILSA_SS/UI/LiquidProgress.swift"
  "$repo_dir/Sources/AILSA_SS/UI/AccountTagView.swift"
  "$repo_dir/Sources/AILSA_SS/UI/AppDesign.swift"
  "$repo_dir/Sources/AILSA_SS/Layout/LayoutRules.swift"
)

printf '[build_app] compiling widget extension\n'
xcrun --sdk macosx swiftc \
  "${common_swift_flags[@]}" \
  -application-extension \
  -module-name AILSA_SSWidgetsMac \
  -o "$widget_binary" \
  "${widget_sources[@]}"

# ---------------------------------------------------------------------------
# Info.plist (resolve every $(...) placeholder from VERSION / constants)
# ---------------------------------------------------------------------------
cp "$repo_dir/Sources/AILSA_SS/Info-macOS.plist" "$app_contents/Info.plist"
cp "$repo_dir/Sources/AILSA_SSWidgets/Info.plist" "$widget_contents/Info.plist"

plist_set_string() {
  if /usr/libexec/PlistBuddy -c "Print :$2" "$1" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :$2 $3" "$1"
  else
    /usr/libexec/PlistBuddy -c "Add :$2 string $3" "$1"
  fi
}

plist_set_string "$app_contents/Info.plist" CFBundleDevelopmentRegion en
plist_set_string "$app_contents/Info.plist" CFBundleDisplayName "$app_display_name"
plist_set_string "$app_contents/Info.plist" CFBundleExecutable AILSA_SS
plist_set_string "$app_contents/Info.plist" CFBundleIconFile AILSASubSwitch.icns
plist_set_string "$app_contents/Info.plist" CFBundleIdentifier "$app_bundle_id"
plist_set_string "$app_contents/Info.plist" CFBundleName "$app_display_name"
plist_set_string "$app_contents/Info.plist" CFBundlePackageType APPL
plist_set_string "$app_contents/Info.plist" CFBundleShortVersionString "$marketing_version"
plist_set_string "$app_contents/Info.plist" CFBundleVersion "$build_number"
plist_set_string "$app_contents/Info.plist" ASSBuildLabel "$build_label"
plist_set_string "$app_contents/Info.plist" ASSBuildDate "$build_date"

plist_set_string "$widget_contents/Info.plist" CFBundleExecutable AILSA_SSWidgetsMac
plist_set_string "$widget_contents/Info.plist" CFBundleIdentifier "$widget_bundle_id"
plist_set_string "$widget_contents/Info.plist" CFBundleShortVersionString "$marketing_version"
plist_set_string "$widget_contents/Info.plist" CFBundleVersion "$build_number"

for info_plist in "$app_contents/Info.plist" "$widget_contents/Info.plist"; do
  plutil -lint "$info_plist" >/dev/null
  if grep -F '$(' "$info_plist" >/dev/null; then
    printf 'Unresolved build setting remained in: %s\n' "$info_plist" >&2
    exit 3
  fi
done

# ---------------------------------------------------------------------------
# Resources (everything under Sources/AILSA_SS/Resources is a runtime asset)
# ---------------------------------------------------------------------------
ditto "$repo_dir/Sources/AILSA_SS/Resources" "$app_resources"
for required_resource in \
  AILSASubSwitch.icns \
  THIRD_PARTY_NOTICES.md \
  AILSA_SS-runtime-pricing-bindings-v1.json \
  en.lproj/Localizable.strings \
  zh-Hans.lproj/Localizable.strings; do
  if [[ ! -f "$app_resources/$required_resource" ]]; then
    printf 'Required runtime resource was not bundled: %s\n' "$required_resource" >&2
    exit 3
  fi
done

# ---------------------------------------------------------------------------
# Sign (inner to outer). Ad-hoc by default; Developer ID via CODESIGN_IDENTITY.
# ---------------------------------------------------------------------------
if [[ "$do_sign" -eq 1 ]]; then
  sign_flags=(--force --sign "$codesign_identity")
  if [[ "$codesign_identity" != "-" ]]; then
    # Hardened runtime + secure timestamp are required for notarization.
    sign_flags+=(--timestamp --options runtime)
  fi
  codesign "${sign_flags[@]}" \
    --entitlements "$repo_dir/AILSA_SSWidgetsMac.entitlements" "$widget_bundle"
  codesign "${sign_flags[@]}" \
    --entitlements "$repo_dir/AILSA_SS.entitlements" "$app_bundle"
  codesign --verify --deep --strict "$app_bundle"
  printf '[build_app] signed with: %s\n' "$codesign_identity"
else
  printf '[build_app] NOT signed (--no-sign)\n'
fi

# ---------------------------------------------------------------------------
# Hygiene check: no builder home path inside the binaries.
# ---------------------------------------------------------------------------
for bin in "$app_binary" "$widget_binary"; do
  if strings -a "$bin" | grep -E '^/Users/|/Volumes/' >/dev/null; then
    printf 'Builder path leaked into %s\n' "$bin" >&2
    exit 3
  fi
done

# ---------------------------------------------------------------------------
# Zip + manifest
# ---------------------------------------------------------------------------
zip_path=""
if [[ "$skip_zip" -eq 0 ]]; then
  zip_path="$output_root/AILSA-SubSwitch-${marketing_version}-${target_triple%%-*}.zip"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_bundle" "$zip_path"
  # Standard `shasum -c` format: "<hash>  <basename>"
  (cd "$(dirname "$zip_path")" && shasum -a 256 "$(basename "$zip_path")" > "$(basename "$zip_path").sha256")
fi

manifest="$output_root/source-manifest.json"
{
  printf '{\n  "marketingVersion": "%s",\n  "buildNumber": "%s",\n  "buildLabel": "%s",\n' \
    "$marketing_version" "$build_number" "$build_label"
  printf '  "gitHead": "%s",\n' "$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null || echo unknown)"
  printf '  "gitDirty": %s,\n' "$([[ -n "$(git -C "$repo_dir" status --porcelain 2>/dev/null)" ]] && echo true || echo false)"
  printf '  "codesignIdentity": "%s",\n' "$([[ "$do_sign" -eq 1 ]] && echo "$codesign_identity" || echo none)"
  printf '  "sources": {\n'
  first=1
  while IFS= read -r f; do
    rel="${f#"$repo_dir"/}"
    hash="$(shasum -a 256 "$f" | awk '{print $1}')"
    [[ $first -eq 1 ]] || printf ',\n'
    first=0
    printf '    "%s": "%s"' "$rel" "$hash"
  done < <(find "$repo_dir/Sources" "$repo_dir/scripts" "$repo_dir/Package.swift" "$repo_dir/VERSION" "$repo_dir/AILSA_SS.entitlements" \
             "$repo_dir/AILSA_SSWidgetsMac.entitlements" -type f -print | sort)
  printf '\n  }\n}\n'
} > "$manifest"

printf '[build_app] app=%s\n' "$app_bundle"
[[ -n "$zip_path" ]] && printf '[build_app] zip=%s\n[build_app] sha256=%s\n' "$zip_path" "$(awk '{print $1}' "$zip_path.sha256")"
printf '[build_app] manifest=%s\n' "$manifest"
