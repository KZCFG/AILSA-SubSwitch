#!/usr/bin/env python3
"""Inventory current public files against Copool's recorded upstream baseline."""
import argparse
import csv
from pathlib import Path
import subprocess

BASE = "3cb6ede534bdbff86804e9beaed567a190dac2f3"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--upstream", type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
subprocess.run(["git", "-C", str(args.upstream), "cat-file", "-e", BASE], check=True)
rows = []
ignored = {".git", ".build", "build", "dist", ".swiftpm", "__pycache__", "xcuserdata", ".codex-artifacts", "artifacts", ".worktrees"}
for path in sorted(root.rglob("*")):
    relative = path.relative_to(root)
    if not path.is_file() or path.is_symlink() or any(p in ignored or p.endswith(".app") for p in relative.parts):
        continue
    if relative.as_posix() == "docs/provenance.csv" or path.name == ".DS_Store":
        continue
    data = path.read_bytes()
    previous = subprocess.run(["git", "-C", str(args.upstream), "show", f"{BASE}:{relative.as_posix()}"], capture_output=True)
    category = "upstream_identical" if previous.returncode == 0 and previous.stdout == data else "upstream_modified" if previous.returncode == 0 else "local_addition"
    rows.append((relative.as_posix(), category, len(data), "MIT; see LICENSE and bundled third-party notices"))
with (root / "docs/provenance.csv").open("w", newline="") as output:
    writer = csv.writer(output, lineterminator="\n")
    writer.writerow(["path", "baseline_comparison", "bytes", "license_note"])
    writer.writerows(rows)
print(f"Inventoried {len(rows)} files against {BASE}.")
