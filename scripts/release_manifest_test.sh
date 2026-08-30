#!/usr/bin/env bash
# Shape and determinism test for scripts/release_manifest.sh.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
tmp="$(mktemp -d "${TMPDIR:-/tmp}/alatyr-release-manifest.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

bash scripts/release_manifest.sh --allow-dirty --output "$tmp/one.json" >/dev/null
bash scripts/release_manifest.sh --allow-dirty --output "$tmp/two.json" >/dev/null
cmp -s "$tmp/one.json" "$tmp/two.json" || {
  echo "FAIL release manifest: repeated generation differs" >&2
  exit 1
}

python3 - "$tmp/one.json" <<'PY'
import json
import re
import sys

manifest = json.load(open(sys.argv[1], encoding="utf-8"))
assert manifest["schema"] == "alatyr.release-manifest/v1"
assert re.fullmatch(r"[0-9a-f]{40}", manifest["commit"])
assert re.fullmatch(r"[0-9a-f]{64}", manifest["source_tree_sha256"])
assert len(manifest["targets"]) >= 7
assert {row["surface"] for row in manifest["targets"]} >= {
    "linux-x86_64", "linux-aarch64", "linux-riscv64", "wasm"
}
assert set(manifest["gates"]) == {"fixpoint", "package", "conformance", "contract"}
assert set(manifest["gates"].values()) <= {"pass", "fail", "not-run", "blocked"}
assert manifest["gates"]["fixpoint"] != "pass", "unrecorded fixpoint must not become green"
print(f"ok   release manifest: {len(manifest['targets'])} targets, deterministic JSON")
PY
