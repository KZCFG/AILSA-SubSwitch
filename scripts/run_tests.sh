#!/bin/bash
# Build and RUN Tests/CopoolTests on a Command Line Tools-only machine.
#   run_tests.sh [--isolate] [--only <substring>] [--repo /path/to/Copool]
# - Uses XCTestRuntime.swift (asserting shim) instead of Apple's XCTest.
# - Generates a main that calls every `func test*` of every direct
#   `XCTestCase` subclass (files importing swift-testing are skipped).
# - Exit code 1 when any test fails. This is not Apple XCTest; see CONTRIBUTING.md.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
only=""
isolate=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --only) only="$2"; shift 2 ;;
    --repo) repo="$2"; shift 2 ;;
    --isolate) isolate=1; shift ;;
    *) echo "unknown arg $1" >&2; exit 2 ;;
  esac
done
tools="$(cd "$(dirname "$0")/testing" && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/ass-tests.XXXXXX")"
trap 'rm -rf "$work"' EXIT
target=arm64-apple-macos14.0
frameworks=(-framework SwiftUI -framework AppKit -framework WidgetKit -framework Security -framework Combine -framework ServiceManagement -framework Network -framework UniformTypeIdentifiers -lcompression)

echo "[1/4] XCTest runtime shim"
xcrun --sdk macosx swiftc -emit-library -emit-module -module-name XCTest -parse-as-library \
  -target "$target" -emit-module-path "$work/XCTest.swiftmodule" -o "$work/libXCTest.dylib" \
  "$tools/XCTestRuntime.swift"

app_sources=()
while IFS= read -r file; do app_sources+=("$file"); done < <(find "$repo/Sources/Copool" -name '*.swift' | sort)
echo "[2/4] Copool library (testable, DEBUG)"
xcrun --sdk macosx swiftc -emit-library -emit-module -module-name Copool -enable-testing -DDEBUG \
  -target "$target" -emit-module-path "$work/Copool.swiftmodule" -o "$work/libCopool.dylib" \
  "${frameworks[@]}" \
  "${app_sources[@]}" 2> "$work/copool-build.log" || { cat "$work/copool-build.log"; exit 1; }

echo "[3/4] generate runner main"
test_files=()
while IFS= read -r file; do test_files+=("$file"); done < <(grep -L '^import Testing' "$repo"/Tests/CopoolTests/*.swift | sort)
python3 - "$work/OfflineTestRunner.swift" "$only" "${test_files[@]}" <<'EOF'
import re, sys
out, only, files = sys.argv[1], sys.argv[2], sys.argv[3:]
cls_re = re.compile(r'^(?:@MainActor\s+)?(?:final\s+)?class\s+(\w+)\s*:\s*XCTestCase\b', re.M)
lines = ["import XCTest", "@testable import Copool", "", "@main struct OfflineTestRunner {", "  @MainActor static func main() async {"]
count = 0
for path in files:
    src = open(path).read()
    for m in cls_re.finditer(src):
        name = m.group(1)
        # class body: from the match to the matching closing brace (brace counting)
        i = src.index("{", m.end()); depth = 0; j = i
        while j < len(src):
            if src[j] == "{": depth += 1
            elif src[j] == "}":
                depth -= 1
                if depth == 0: break
            j += 1
        body = src[i:j]
        for fm in re.finditer(r'^\s*(?:@MainActor\s+)?func\s+(test\w*)\s*\(\s*\)\s*(async)?\s*(throws)?', body, re.M):
            fn, is_async, throws = fm.group(1), bool(fm.group(2)), bool(fm.group(3))
            full = f"{name}.{fn}"
            if only and only not in full: continue
            count += 1
            call = ("try " if throws else "") + ("await " if is_async else "") + f"t.{fn}()"
            lines.append(f'    await XCTRuntime.run("{full}") {{')
            lines.append(f'      let t = {name}()')
            lines.append('      try { try t.setUpWithError() }(); { t.setUp() }(); try await t.setUp()')
            lines.append(f'      do {{ {call} }} catch {{ XCTRuntime.record("threw \\(error)", file: "{path}", line: 0) }}')
            lines.append('      try await t.tearDown(); { t.tearDown() }(); try { try t.tearDownWithError() }(); await t.runTeardownBlocks()')
            lines.append('    }')
lines += ["    exit(XCTRuntime.summary())", "  }", "}"]
open(out, "w").write("\n".join(lines) + "\n")
print(f"  {count} test methods in {len(files)} files")
EOF

echo "[4/4] compile + run"
xcrun --sdk macosx swiftc -module-name CopoolTests -target "$target" -DDEBUG -parse-as-library -suppress-warnings \
  -I "$work" -L "$work" -lXCTest -lCopool "${frameworks[@]}" \
  -Xlinker -rpath -Xlinker "$work" \
  -o "$work/runner" "${test_files[@]}" "$work/OfflineTestRunner.swift" 2> "$work/tests-build.log" || { cat "$work/tests-build.log"; exit 1; }
# L10n resolves through Bundle.main (= the runner's directory here); give it
# the app's .lproj tables so localization-dependent tests see real strings.
cp -R "$repo"/Sources/Copool/Resources/*.lproj "$work/"
cd "$work"
if [[ $isolate -eq 1 ]]; then
  # One process per test class so a crash in one class does not hide the rest.
  classes=$(grep -o 'run("[A-Za-z0-9_]*\.' OfflineTestRunner.swift | sed 's/run("//; s/\.$//' | sort -u)
  : > run.log
  status=0
  for cls in $classes; do
    if ! perl -e 'alarm shift; exec @ARGV' 300 ./runner "$cls." >> run.log 2>&1; then
      status=1; echo "CRASH/FAIL in $cls (see run.log)" | tee -a run.log
    fi
  done
  grep -E '^(SUMMARY|  FAIL|CRASH)' run.log
  echo "classes=$(echo "$classes" | wc -w | tr -d ' ') passed=$(grep -h '^SUMMARY' run.log | awk '{s+=$2} END {print s+0}') failed=$(grep -h '^SUMMARY' run.log | awk '{s+=$4} END {print s+0}')"
  exit $status
fi
perl -e 'alarm shift; exec @ARGV' 900 ./runner 2>&1 | tee "$work/run.log" | grep -v '^RUN '
