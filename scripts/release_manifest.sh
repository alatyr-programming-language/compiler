#!/usr/bin/env bash
# Emit a stable, provenance-only release manifest. It never runs a project gate or exposes secrets.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

allow_dirty=0
output="target/release-manifest.json"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --allow-dirty)
      allow_dirty=1
      shift
      ;;
    --output)
      [ "$#" -ge 2 ] || { echo "usage: $0 [--allow-dirty] [--output PATH]" >&2; exit 2; }
      output="$2"
      shift 2
      ;;
    --output=*)
      output="${1#--output=}"
      shift
      ;;
    *)
      echo "usage: $0 [--allow-dirty] [--output PATH]" >&2
      exit 2
      ;;
  esac
done

dirty=0
if [ -n "$(git status --porcelain --untracked-files=all)" ]; then dirty=1; fi
if [ "$dirty" = 1 ] && [ "$allow_dirty" != 1 ]; then
  echo "release manifest: working tree is dirty; use --allow-dirty for an inspection manifest" >&2
  exit 3
fi

mkdir -p "$(dirname "$output")"
python3 - "$ROOT" "$output" "$dirty" <<'PY'
import csv
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys

root = pathlib.Path(sys.argv[1]).resolve()
output = pathlib.Path(sys.argv[2]).resolve()
dirty = bool(int(sys.argv[3]))

def run(*args):
    try:
        result = subprocess.run(args, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                check=False, text=True,
                                env={"PATH": os.environ.get("PATH", "/usr/bin:/bin")})
    except OSError:
        return "unavailable"
    value = result.stdout.strip().splitlines()
    return value[0].strip() if result.returncode == 0 and value else "unavailable"

def git(*args):
    result = subprocess.run(("git",) + args, cwd=root, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, check=True, text=True)
    return result.stdout

def relative(path):
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        return None

paths = [pathlib.Path(item.decode("utf-8")) for item in subprocess.run(
    ("git", "ls-files", "-co", "--exclude-standard", "-z"), cwd=root,
    stdout=subprocess.PIPE, check=True).stdout.split(b"\0") if item]
output_rel = relative(output)
paths = sorted(path for path in paths if path.as_posix() != output_rel)
tree_hash = hashlib.sha256()
for path in paths:
    full = root / path
    if not full.is_file():
        continue
    name = path.as_posix().encode("utf-8")
    data = full.read_bytes()
    tree_hash.update(len(name).to_bytes(8, "big"))
    tree_hash.update(name)
    tree_hash.update(len(data).to_bytes(8, "big"))
    tree_hash.update(data)

seed = []
for path in sorted(path for path in paths if path.as_posix().startswith("seed/")):
    full = root / path
    if full.is_file():
        seed.append({"path": path.as_posix(), "sha256": hashlib.sha256(full.read_bytes()).hexdigest()})

readme = (root / "README.md").read_text(encoding="utf-8")
spec_match = re.search(r"spec revision \*\*([^*]+)\*\* \(tag `([^`]+)`, `([^`]+)`\) plus .*?spec `main` `([^`]+)`", readme, re.S)
if spec_match:
    spec = {
        "version": spec_match.group(1),
        "tag": spec_match.group(2),
        "tag_revision": spec_match.group(3),
        "main_revision": spec_match.group(4),
    }
else:
    spec = {"version": "unparsed", "tag": "unparsed", "tag_revision": "unparsed", "main_revision": "unparsed"}

matrix = []
with (root / "docs/target-support.tsv").open(newline="", encoding="utf-8") as stream:
    for row in csv.DictReader(stream, delimiter="\t"):
        matrix.append(dict(row))

gate_dir = root / "target/release-gates"
def gate_status(name):
    path = gate_dir / f"{name}.status"
    if not path.is_file():
        return "not-run"
    value = path.read_text(encoding="utf-8").strip()
    return value if value in {"pass", "fail", "not-run", "blocked"} else "blocked"

compiler = root / "target/debug/alatyr"
manifest = {
    "schema": "alatyr.release-manifest/v1",
    "commit": git("rev-parse", "HEAD").strip(),
    "dirty": dirty,
    "source_tree_sha256": tree_hash.hexdigest(),
    "seed": seed,
    "spec": spec,
    "targets": matrix,
    "tools": {
        "compiler": run(str(compiler), "--version") if compiler.exists() else "not-built",
        "assembler": run("as", "--version"),
        "linker": run("ld", "--version"),
        "git": run("git", "--version"),
        "python": run("python3", "--version"),
    },
    "gates": {name: gate_status(name) for name in ("fixpoint", "package", "conformance", "contract")},
}
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(manifest, ensure_ascii=True, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(f"release manifest: {output}")
print(f"release manifest: source_tree_sha256={manifest['source_tree_sha256']}")
print(f"release manifest: gates={json.dumps(manifest['gates'], sort_keys=True)}")
PY
