#!/usr/bin/env bash
# scripts/ir_ap_names_check.sh — the fixed-array parameter plan sees every name the compiler calls
# without writing it at the call site (#1641's second review, B1).
#
# `ir::ap_plan_begin` (src/ir.al) finds the callers of a function with a fixed-array parameter from the
# source text. A call the compiler synthesizes — the driver's `w[i] = v` → `index_set(…)`, a `for` over an
# iterator → `next(…)`, the comparison route's `eq`/`lt`, a declaration picked by a literal name — names
# its callee nowhere in the text, so `ir::ap_synth_name` holds every such name. This check reads the
# helpers that synthesize or pick a callee by a literal name and fails when one names something
# `ap_synth_name` lacks. It sees those helpers' shapes only: a brand-new helper is a reviewer's catch,
# and its first use should be added to the patterns below.
#
#   scripts/ir_ap_names_check.sh [ROOT]     check the tree at ROOT (default: this repository)
#   scripts/ir_ap_names_check.sh --self-test
set -u

extract_used() {
  local r="$1"
  {
    # driver: the index-operator and iterator desugars
    grep -ohE '(d_idxop_call|d_idxop_base|d_iterfor_lit)\([^"]*"[A-Za-z_][A-Za-z0-9_]*"' "$r"/src/driver.al
    # parser: identifiers it synthesizes into calls (`alloc_into`, the `defer` markers)
    grep -ohE 'synth_ident_span\(pc, "[A-Za-z_][A-Za-z0-9_]*"' "$r"/src/parser.al
    # declarations looked up by a literal name for a call the source does not write
    grep -ohE '(decl_by_lit_name|mark_lit|named_op_decl_idx)\([^"]*"[A-Za-z_][A-Za-z0-9_]*"' "$r"/src/*.al "$r"/src/*/*.al
    # a declaration chosen by comparing its own name with a literal
    grep -ohE 'name_start\)?, *[A-Za-z0-9_.]+\) *== *"[A-Za-z_][A-Za-z0-9_]*"' "$r"/src/*.al "$r"/src/*/*.al
    # the comparison route's callee names
    awk '/^cmp_route_name := fn/{on=1} on && /return "[A-Za-z_]+"/{print} on && /^}/{exit}' "$r"/src/lower.al
  } | grep -oE '"[A-Za-z_][A-Za-z0-9_]*"' | tr -d '"' | sort -u
}

extract_listed() {
  awk '/^ap_synth_name := fn/{on=1} on{print} on && /^}/{exit}' "$1"/src/ir.al \
    | grep -oE 'nm == "[A-Za-z_][A-Za-z0-9_]*"' | grep -oE '"[^"]*"' | tr -d '"' | sort -u
}

check() {
  local r="$1" used listed missing
  used="$(extract_used "$r")"
  listed="$(extract_listed "$r")"
  if [ -z "$listed" ]; then echo "ir_ap_names: FAIL — no ap_synth_name list found in $r/src/ir.al"; return 1; fi
  if [ -z "$used" ]; then echo "ir_ap_names: FAIL — no synthesized name found; the patterns no longer match the tree"; return 1; fi
  missing="$(comm -23 <(echo "$used") <(echo "$listed"))"
  echo "ir_ap_names: synthesized=$(echo "$used" | wc -l | tr -d ' ') listed=$(echo "$listed" | wc -l | tr -d ' ')"
  if [ -n "$missing" ]; then
    echo "ir_ap_names: FAIL — synthesized but not held by ir::ap_synth_name (src/ir.al):"
    echo "$missing" | sed 's/^/  /'
    return 1
  fi
  echo "ir_ap_names: OK"
}

self_test() {
  local here t fails=0
  here="$(cd "$(dirname "$0")/.." && pwd)"
  t="$(mktemp -d "${TMPDIR:-/tmp}/ir_ap_names.XXXXXX")"
  trap 'rm -rf "$t"' RETURN
  mkdir -p "$t/src/lower"
  cp "$here"/src/*.al "$t/src/"
  cp "$here"/src/lower/*.al "$t/src/lower/"
  # control: the tree as it is passes
  if ! check "$t" > /dev/null; then echo "self-test FAIL: control tree refused"; fails=1; fi
  # plant: the driver synthesizes a new name
  printf '\nplanted := fn() { x := d_iterfor_lit(na, src_int, "planted_name", ptr(l)) }\n' >> "$t/src/driver.al"
  if check "$t" > /dev/null; then echo "self-test FAIL: a new driver-synthesized name passed"; fails=1; fi
  cp "$here/src/driver.al" "$t/src/driver.al"
  # plant: a declaration picked by a literal name
  printf '\nplanted := fn() -> bool { str_at((src + d.name_start), d.name_len) == "planted_pick" }\n' >> "$t/src/lower/mono.al"
  if check "$t" > /dev/null; then echo "self-test FAIL: a new literal-name pick passed"; fails=1; fi
  cp "$here/src/lower/mono.al" "$t/src/lower/mono.al"
  # plant: a name dropped from the list
  sed -i.bak 's/nm == "index_set" or //' "$t/src/ir.al"
  if check "$t" > /dev/null; then echo "self-test FAIL: a name dropped from ap_synth_name passed"; fails=1; fi
  if [ "$fails" = 0 ]; then echo "ir_ap_names self-test: OK (1 control, 3 plants)"; fi
  return "$fails"
}

if [ "${1:-}" = "--self-test" ]; then self_test; exit $?; fi
check "${1:-$(cd "$(dirname "$0")/.." && pwd)}"
