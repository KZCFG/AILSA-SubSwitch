#!/usr/bin/env bash
set -euo pipefail

# Local release retention for AILSA SubSwitch.
#
# After a verified replacement, retain only AILSA SubSwitch.app.
# The previous version is a temporary rollback candidate until verification;
# after success it is moved to Trash, never retained as an installed Legacy app.
#
# Everything this script prunes is moved to the user's Trash, never removed
# permanently. It only considers exact AILSA SubSwitch/AILSA_SS app bundles and
# matching zip/dmg archives under explicitly supplied prune roots; reports,
# source code, account data, credentials, and unrelated projects are out of
# scope by construction.

script_name="$(basename "$0")"
apply_changes=0
prune_only=0
new_app=""
installed_app="/Applications/AILSA SubSwitch.app"
legacy_app="/Applications/AILSA SubSwitch (Legacy).app"
keep_archive=""
trash_dir="${HOME}/.Trash"
timestamp="$(date +%Y%m%d-%H%M%S)"
trash_sequence=0
prune_roots=()
moved_items=()

usage() {
  cat <<'EOF'
Usage:
  retain_local_versions.sh --new-app <path-to-new.app> --keep-archive <latest.zip> \
    --prune-root <directory> [--prune-root <directory> ...] --apply

  retain_local_versions.sh --prune-only --keep-archive <latest.zip> \
    --prune-root <directory> [--prune-root <directory> ...] --apply

By default the command is a dry run. Add --apply only after the new app and
the latest archive have been verified. The command moves superseded app bundles
and matching old zip/dmg files to Trash; it never permanently deletes them.

Options:
  --new-app <path>       Verified app bundle that will become the current app.
  --prune-only           Do not install an app; prune only explicit roots.
  --keep-archive <path>  The single latest zip/dmg archive to retain.
  --prune-root <path>    A narrow, explicit directory to scan for old exact
                         AILSA SubSwitch/AILSA_SS .app, .zip, or .dmg artifacts.
                         May be repeated.
  --installed-app <path> Current app path. Default: /Applications/AILSA SubSwitch.app
  --legacy-app <path>    Temporary rollback path. Default: /Applications/AILSA SubSwitch (Legacy).app
  --trash-dir <path>     Trash destination. Default: $HOME/.Trash
  --apply                Perform the otherwise dry-run moves.
  --help                 Show this message.

Close AILSA SubSwitch before a normal replacement run. Previous versions
are moved to Trash only after the replacement passes signature verification.
EOF
}

log() {
  printf '[retain_local_versions] %s\n' "$*"
}

fail() {
  printf '[retain_local_versions] %s\n' "$*" >&2
  exit 1
}

canonical_existing_path() {
  local item="$1"
  local parent

  [[ -e "$item" || -L "$item" ]] || fail "Path does not exist: $item"
  parent="$(cd "$(dirname "$item")" && pwd -P)"
  printf '%s/%s\n' "$parent" "$(basename "$item")"
}

is_exact_app_bundle() {
  case "$(basename "$1")" in
    'AILSA_SS.app'|AILSA\ SubSwitch*.app|.AILSA\ SubSwitch*-stage.app)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_exact_archive() {
  case "$(basename "$1")" in
    AILSA*SubSwitch*.zip|AILSA_SS*.zip|AILSA*SubSwitch*.dmg|AILSA_SS*.dmg)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

add_prune_root() {
  local requested="$1"
  local root
  local existing

  root="$(canonical_existing_path "$requested")"
  [[ -d "$root" ]] || fail "Prune root is not a directory: $requested"

  case "$root" in
    /|"${HOME}"|/Applications|/System|/Users)
      fail "Refusing broad prune root: $root"
      ;;
  esac

  if [[ "${#prune_roots[@]}" -gt 0 ]]; then
    for existing in "${prune_roots[@]}"; do
      case "$root" in
        "$existing"|"$existing"/*)
          fail "Prune roots must not overlap: $root and $existing"
          ;;
      esac
      case "$existing" in
        "$root"/*)
          fail "Prune roots must not overlap: $root and $existing"
          ;;
      esac
    done
  fi

  prune_roots+=("$root")
}

next_trash_destination() {
  local source="$1"
  local category="$2"
  local candidate

  while true; do
    trash_sequence=$((trash_sequence + 1))
    candidate="$trash_dir/${timestamp}-${trash_sequence}-${category}-$(basename "$source")"
    if [[ ! -e "$candidate" && ! -L "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
}

move_to_trash() {
  local source="$1"
  local category="$2"
  local destination

  [[ -e "$source" || -L "$source" ]] || return 0

  if [[ "$apply_changes" -eq 0 ]]; then
    log "dry run: would move to Trash [$category] $source"
    return 0
  fi

  mkdir -p "$trash_dir"
  destination="$(next_trash_destination "$source" "$category")"
  mv "$source" "$destination"
  moved_items+=("$destination")
  log "moved to Trash [$category] $source"
}

verify_app_bundle() {
  local app_path="$1"

  [[ -d "$app_path" ]] || fail "Expected an app bundle: $app_path"
  is_exact_app_bundle "$app_path" || fail "Refusing a non-SubSwitch app bundle: $app_path"
  [[ -f "$app_path/Contents/Info.plist" ]] || fail "Missing Info.plist: $app_path"
  [[ -x "$app_path/Contents/MacOS/AILSA_SS" ]] || fail "Missing AILSA_SS executable: $app_path"
  codesign --verify --deep --strict "$app_path"
}

bundle_build_number() {
  /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$1/Contents/Info.plist"
}

build_is_newer() {
  local candidate="$1"
  local installed="$2"
  # Historical builds use YYYYMMDDNN while date-only releases use YYYYMMDD.
  # Normalize both to a date plus a two-digit sequence before comparing so a
  # new date-only build is not rejected as numerically smaller than yesterday's
  # sequenced build.
  if [[ "${#candidate}" -eq 8 ]]; then candidate="${candidate}00"; fi
  if [[ "${#installed}" -eq 8 ]]; then installed="${installed}00"; fi
  [[ "$candidate" =~ ^[0-9]+$ && "$installed" =~ ^[0-9]+$ ]] || return 1
  (( 10#$candidate > 10#$installed ))
}

collect_prune_targets() {
  local root
  local item

  # macOS Bash 3 treats an empty array expansion as unset under nounset.
  [[ "${#prune_roots[@]}" -gt 0 ]] || return 0
  for root in "${prune_roots[@]}"; do
    while IFS= read -r -d '' item; do
      prune_targets+=("$item")
    done < <(
      find "$root" -type d \
        \( -name 'AILSA_SS.app' -o -name 'AILSA SubSwitch*.app' \) \
        -prune -print0
    )

    while IFS= read -r -d '' item; do
      if [[ "$item" == "$keep_archive" ]]; then
        log "keeping latest archive $item"
      else
        prune_targets+=("$item")
      fi
    done < <(
      find "$root" -type f \
        \( -name 'AILSA*SubSwitch*.zip' -o -name 'AILSA_SS*.zip' -o -name 'AILSA*SubSwitch*.dmg' -o -name 'AILSA_SS*.dmg' \) \
        -print0
    )
  done
}

install_replacement() {
  local install_dir
  local stage_app
  local legacy_hold
  local new_build
  local installed_build=""

  [[ "$new_app" != "$installed_app" && "$new_app" != "$legacy_app" && "$installed_app" != "$legacy_app" ]] || fail "Source, installed and rollback paths must differ"
  verify_app_bundle "$new_app"
  new_build="$(bundle_build_number "$new_app")"
  install_dir="$(dirname "$installed_app")"
  [[ -d "$install_dir" ]] || fail "Install directory does not exist: $install_dir"
  is_exact_app_bundle "$installed_app" || fail "Installed app must be named AILSA SubSwitch.app"
  is_exact_app_bundle "$legacy_app" || fail "Legacy app must be named AILSA SubSwitch (Legacy).app"

  if [[ -d "$installed_app" ]]; then
    verify_app_bundle "$installed_app"
    installed_build="$(bundle_build_number "$installed_app")"
    if [[ "$new_build" =~ ^[0-9]+$ && "$installed_build" =~ ^[0-9]+$ ]] \
      && ! build_is_newer "$new_build" "$installed_build"; then
      fail "New build ($new_build) must be newer than installed build ($installed_build)"
    fi
  fi

  if [[ "$apply_changes" -eq 1 && -f "$installed_app/Contents/MacOS/AILSA_SS" ]]; then
    # lsof also reports system services such as tccd reading a signed binary;
    # that is not an app instance and must not block a replacement. Match the
    # exact executable (including spaces) in the process comm column instead.
    local running_pid
    running_pid="$(ps -axo pid=,comm= | awk -v executable="$installed_app/Contents/MacOS/AILSA_SS" '{ pid = $1; sub(/^[[:space:]]*[0-9]+[[:space:]]+/, ""); if ($0 == executable) print pid }')"
    if [[ -n "$running_pid" ]]; then
      fail "Installed app is running (pid $running_pid); close it before replacement. No files changed."
    fi
  fi

  stage_app="$install_dir/.AILSA SubSwitch-${new_build}-stage.app"
  legacy_hold="$install_dir/.AILSA SubSwitch-Legacy-${timestamp}-hold.app"
  [[ ! -e "$stage_app" ]] || fail "Staging path already exists: $stage_app"
  [[ ! -e "$legacy_hold" ]] || fail "Legacy hold path already exists: $legacy_hold"

  if [[ "$apply_changes" -eq 0 ]]; then
    log "dry run: would install $new_app as $installed_app"
    if [[ -d "$legacy_app" ]]; then
      log "dry run: would replace existing legacy app $legacy_app"
    fi
    if [[ -d "$installed_app" ]]; then
      log "dry run: would hold $installed_app for rollback, then move it to Trash after verification"
    fi
    log "dry run: would move the installed source copy to Trash $new_app"
    return 0
  fi

  ditto "$new_app" "$stage_app"
  verify_app_bundle "$stage_app"

  if [[ -d "$legacy_app" ]]; then
    mv "$legacy_app" "$legacy_hold"
  fi

  if [[ -d "$installed_app" ]]; then
    mv "$installed_app" "$legacy_app"
  fi

  if ! mv "$stage_app" "$installed_app"; then
    if [[ -d "$legacy_app" ]]; then
      mv "$legacy_app" "$installed_app"
    fi
    if [[ -d "$legacy_hold" ]]; then
      mv "$legacy_hold" "$legacy_app"
    fi
    fail "Unable to activate the staged app; restored the prior local state"
  fi

  if ! codesign --verify --deep --strict "$installed_app"; then
    mv "$installed_app" "$stage_app"
    if [[ -d "$legacy_app" ]]; then
      mv "$legacy_app" "$installed_app"
    fi
    if [[ -d "$legacy_hold" ]]; then
      mv "$legacy_hold" "$legacy_app"
    fi
    fail "Installed app verification failed; restored the prior local state"
  fi

  if [[ -d "$legacy_hold" ]]; then
    move_to_trash "$legacy_hold" "superseded-legacy"
  fi
  move_to_trash "$new_app" "installed-source"
  log "retained current app $installed_app"
  if [[ -d "$legacy_app" ]]; then
    move_to_trash "$legacy_app" "superseded-app"
  fi
}

prune_targets=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --new-app)
      [[ $# -ge 2 ]] || fail "--new-app needs a path"
      new_app="$(canonical_existing_path "$2")"
      shift 2
      ;;
    --prune-only)
      prune_only=1
      shift
      ;;
    --keep-archive)
      [[ $# -ge 2 ]] || fail "--keep-archive needs a path"
      keep_archive="$(canonical_existing_path "$2")"
      shift 2
      ;;
    --prune-root)
      [[ $# -ge 2 ]] || fail "--prune-root needs a path"
      add_prune_root "$2"
      shift 2
      ;;
    --installed-app)
      [[ $# -ge 2 ]] || fail "--installed-app needs a path"
      installed_app="$2"
      shift 2
      ;;
    --legacy-app)
      [[ $# -ge 2 ]] || fail "--legacy-app needs a path"
      legacy_app="$2"
      shift 2
      ;;
    --trash-dir)
      [[ $# -ge 2 ]] || fail "--trash-dir needs a path"
      trash_dir="$2"
      shift 2
      ;;
    --apply)
      apply_changes=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

if [[ "$prune_only" -eq 1 && -n "$new_app" ]]; then
  fail "--prune-only cannot be combined with --new-app"
fi

if [[ "$prune_only" -eq 0 && -z "$new_app" ]]; then
  fail "--new-app is required unless --prune-only is used"
fi

if [[ "${#prune_roots[@]}" -gt 0 && -z "$keep_archive" ]]; then
  fail "--keep-archive is required when pruning release roots"
fi

if [[ -n "$keep_archive" ]]; then
  [[ -f "$keep_archive" ]] || fail "Latest archive is not a file: $keep_archive"
  is_exact_archive "$keep_archive" || fail "Latest archive is not an AILSA SubSwitch/AILSA_SS zip or dmg: $keep_archive"
fi

if [[ "$prune_only" -eq 0 ]]; then
  install_replacement
fi

if [[ "$prune_only" -eq 1 && -d "$legacy_app" ]]; then
  verify_app_bundle "$installed_app"
  [[ "$legacy_app" != "$installed_app" ]] || fail "Rollback and installed paths must differ"
  move_to_trash "$legacy_app" "superseded-app"
fi

collect_prune_targets
for item in ${prune_targets[@]+"${prune_targets[@]}"}; do
  # `find /Applications` may print a double-leading slash on macOS. Normalize
  # it before comparing against the protected current-app path; otherwise the
  # retention pass could mistake the freshly installed app for an old bundle.
  while [[ "$item" == //* ]]; do
    item="${item#/}"
  done
  if [[ "$item" != /* ]]; then
    item="/$item"
  fi
  if [[ "$item" == "$installed_app" ]]; then
    log "keeping current app $item"
  elif is_exact_app_bundle "$item"; then
    move_to_trash "$item" "old-app"
  elif is_exact_archive "$item"; then
    move_to_trash "$item" "old-archive"
  else
    fail "Unexpected prune target: $item"
  fi
done

if [[ "$apply_changes" -eq 0 ]]; then
  log "dry run complete; rerun with --apply after reviewing this plan"
else
  log "retention complete; moved ${#moved_items[@]} item(s) to Trash"
fi
