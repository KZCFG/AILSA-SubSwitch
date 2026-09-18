#!/bin/bash
set -euo pipefail

# Propagate the repo-root VERSION file into the Xcode project descriptions.
# scripts/build_app.sh reads VERSION directly; this keeps project.yml and
# AILSA_SS.xcodeproj/project.pbxproj (used by Xcode / release_macos.sh) in sync.
#
#   scripts/sync_version.sh          # rewrite
#   scripts/sync_version.sh --check  # exit 1 if anything is out of sync

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
version_file="$repo_dir/VERSION"
check_only=0
[[ "${1:-}" == "--check" ]] && check_only=1

read_key() {
  local value
  value="$(sed -n "s/^$1=//p" "$version_file" | head -n1)"
  [[ -n "$value" ]] || { printf 'VERSION lacks %s\n' "$1" >&2; exit 2; }
  printf '%s' "$value"
}
marketing="$(read_key MARKETING_VERSION)"
build="$(read_key BUILD_NUMBER)"
label="$(read_key BUILD_LABEL)"

pbxproj="$repo_dir/AILSA_SS.xcodeproj/project.pbxproj"
project_yml="$repo_dir/project.yml"

expected_pbx=(
  "MARKETING_VERSION = $marketing;"
  "CURRENT_PROJECT_VERSION = $build;"
  "ASS_BUILD_LABEL = $label;"
)
expected_yml=(
  "MARKETING_VERSION: $marketing"
  "CURRENT_PROJECT_VERSION: $build"
  "ASS_BUILD_LABEL: $label"
)

status=0
if [[ "$check_only" -eq 1 ]]; then
  for e in "${expected_pbx[@]}"; do grep -qF "$e" "$pbxproj" || { printf 'pbxproj missing: %s\n' "$e"; status=1; }; done
  for e in "${expected_yml[@]}"; do grep -qF "$e" "$project_yml" || { printf 'project.yml missing: %s\n' "$e"; status=1; }; done
  if grep -E 'MARKETING_VERSION = |CURRENT_PROJECT_VERSION = |ASS_BUILD_LABEL = ' "$pbxproj" \
     | grep -v -F -e "${expected_pbx[0]}" -e "${expected_pbx[1]}" -e "${expected_pbx[2]}" >/dev/null; then
    printf 'pbxproj has stale version values\n'; status=1
  fi
  [[ $status -eq 0 ]] && printf 'version in sync: %s (%s) %s\n' "$marketing" "$build" "$label"
  exit $status
fi

sed -i '' \
  -e "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = $marketing;/" \
  -e "s/CURRENT_PROJECT_VERSION = [^;]*;/CURRENT_PROJECT_VERSION = $build;/" \
  -e "s/ASS_BUILD_LABEL = [^;]*;/ASS_BUILD_LABEL = $label;/" \
  "$pbxproj"
sed -i '' \
  -e "s/MARKETING_VERSION: .*/MARKETING_VERSION: $marketing/" \
  -e "s/CURRENT_PROJECT_VERSION: .*/CURRENT_PROJECT_VERSION: $build/" \
  -e "s/ASS_BUILD_LABEL: .*/ASS_BUILD_LABEL: $label/" \
  "$project_yml"
plutil -lint "$pbxproj" >/dev/null
printf 'synced: %s (%s) %s\n' "$marketing" "$build" "$label"
