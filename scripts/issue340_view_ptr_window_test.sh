#!/usr/bin/env bash
# scripts/issue340_view_ptr_window_test.sh — issue #340: the inferred `q := <view>.ptr` byte-pointer
# recovery must be bounded by the SOURCE LENGTH, not by a fixed 512-byte window.
#
# THE DEFECT THIS LOCKS. `lower::byte_ptr_local` recovers "this local is a `ptr(u8)`" by scanning the
# source forward from the binding's name span. It used to stop at `name_end + 512`. Grammar §2.5 lets
# valid source put arbitrary whitespace between the name and `:=`, so once the `:=`/`<ident>.ptr` text
# crossed that window the scan answered false, `deref_pointee_bytes` fell back to its word-sized
# default, and `deref(q)` loaded EIGHT bytes instead of one. `check` stayed green: the program was
# accepted and produced a clean WRONG VALUE (Types §9.4 / appendix 160 §3.5 — `str` is `{ptr : ptr(u8),
# len}`, so `deref(s.ptr)` is one byte).
#
# The boundary is exact for the shape `q<gap>:= s.ptr`, because the identifier walk must still find the
# `.` under `p < name_end + 512`: gap 507 was the last accepted spelling, gap 508 the first wrong one.
# Both neighbours are asserted, so a fix that merely enlarges the constant fails this test.
#
# Run standalone after building Stage1:
#   ALATYR=target/debug/alatyr bash scripts/issue340_view_ptr_window_test.sh          # fixed tree
#   ALATYR=<parent>/target/debug/alatyr bash scripts/issue340_view_ptr_window_test.sh parent
# The fixtures are GENERATED, so this regression adds no corpus-oracle row, and the asserted x86 load
# widths are checked here rather than spelled in the fixture source (needle discipline).
set -eu
set -o pipefail

: "${ALATYR:?ALATYR must name the compiler under test}"
mode="${1:-fixed}"
case "$mode" in
  fixed|parent) ;;
  *) echo "usage: $0 [fixed|parent]" >&2; exit 2 ;;
esac

work="$(mktemp -d "${TMPDIR:-/tmp}/alatyr-issue340.XXXXXX")"
trap 'rm -rf "$work"' EXIT

gap() { printf '%*s' "$1" ''; }

## `q := s.ptr` off a str LITERAL local. The string's later bytes are non-zero, so a word-sized load
## is observable through the comparison rather than only through a mod-256 exit code.
write_str_literal() { # path, gap
  {
    printf '%s\n' \
      'main := fn() -> u64 {' \
      '  s := "ABCDEFGH"'
    printf '  q%s:= s.ptr\n' "$(gap "$2")"
    printf '%s\n' \
      '  if deref(q) == 65 { return 42 }' \
      '  return 100' \
      '}'
  } > "$1"
}

## The `bytes(<str>)` view dual — a different slot kind reaching the same recovery.
write_bytes_view() { # path, gap
  {
    printf '%s\n' \
      'main := fn() -> u64 {' \
      '  s := "ABCDEFGH"' \
      '  b := bytes(s)'
    printf '  q%s:= b.ptr\n' "$(gap "$2")"
    printf '%s\n' \
      '  if deref(q) == 65 { return 42 }' \
      '  return 101' \
      '}'
  } > "$1"
}

## The CALL-bound str dual.
write_call_view() { # path, gap
  {
    printf '%s\n' \
      'rd := fn() -> str { return "ABCDEFGH" }' \
      'main := fn() -> u64 {' \
      '  t := rd()'
    printf '  q%s:= t.ptr\n' "$(gap "$2")"
    printf '%s\n' \
      '  if deref(q) == 65 { return 42 }' \
      '  return 102' \
      '}'
  } > "$1"
}

## The ANNOTATED sibling. It resolves through `local_ptr_pointee_span`, which is already bounded by the
## published source extent, so it must answer 42 on BOTH compilers: this pins that the fix stays inside
## the inferred-binding path and does not become the reason the annotated path works.
write_annotated() { # path, gap
  {
    printf '%s\n' \
      'main := fn() -> u64 {' \
      '  s := "ABCDEFGH"'
    printf '  q%s: ptr(u8) = s.ptr\n' "$(gap "$2")"
    printf '%s\n' \
      '  if deref(q) == 65 { return 42 }' \
      '  return 103' \
      '}'
  } > "$1"
}

## A struct FIELD holding a `ptr(u8)` is not the `<view>.ptr` shape this helper recovers; it keeps the
## word-sized fallback on both compilers. Guards against a fix that widens the shape it fires on.
write_field_shape() { # path, gap
  {
    printf '%s\n' \
      'Box := struct { p : ptr(u8) }' \
      'main := fn() -> u64 {' \
      '  s := "ABCDEFGH"' \
      '  b := Box(p = s.ptr)'
    printf '  q%s:= b.p\n' "$(gap "$2")"
    printf '%s\n' \
      '  if deref(q) == 65 { return 42 }' \
      '  return 104' \
      '}'
  } > "$1"
}

write_str_literal "$work/control_507.al" 507
write_str_literal "$work/boundary_508.al" 508
write_str_literal "$work/far_2000.al" 2000
write_bytes_view  "$work/bytes_600.al" 600
write_call_view   "$work/call_600.al" 600
write_annotated   "$work/annotated_600.al" 600
write_field_shape "$work/field_600.al" 600

## The whole point is that `check` accepts every one of these: the old defect was a wrong VALUE, not a
## diagnostic, so a fixture that started failing `check` would prove something else entirely.
for f in control_507 boundary_508 far_2000 bytes_600 call_600 annotated_600 field_600; do
  if ! "$ALATYR" check "$work/$f.al" >"$work/$f.check" 2>&1; then
    echo "FAIL issue340_$f: check rejected a valid program" >&2
    sed -n '1,5p' "$work/$f.check" >&2
    exit 1
  fi
done
echo 'ok   issue340: check accepted all seven spellings'

run_case() { # name, source, want
  local name="$1" source="$2" want="$3" out="$work/$1.out" got
  if ! "$ALATYR" -o "$out" "$source" >"$work/$1.build" 2>&1; then
    echo "FAIL issue340_$name: build failed" >&2
    sed -n '1,5p' "$work/$1.build" >&2
    exit 1
  fi
  if "$out" >/dev/null 2>&1; then got=0; else got=$?; fi
  if [ "$got" != "$want" ]; then
    echo "FAIL issue340_$name: got $got want $want" >&2
    exit 1
  fi
  echo "ok   issue340_$name: $got"
}

## The x86 load width for the boundary spelling, read out of the emitted GAS. `movq (%rax), %rax` is
## the old eight-byte read; `movzbq (%rax), %rax` is the single byte Types §9.4 requires.
assert_load() { # source, wanted-insn, forbidden-insn, label
  local source="$1" want="$2" deny="$3" label="$4" gas="$work/$4.gas"
  "$ALATYR" "$source" > "$gas" 2>/dev/null
  if ! grep -qF "$want" "$gas"; then
    echo "FAIL issue340_$label: emitted GAS lacks '$want'" >&2
    exit 1
  fi
  if grep -qF "$deny" "$gas"; then
    echo "FAIL issue340_$label: emitted GAS still contains '$deny'" >&2
    exit 1
  fi
  echo "ok   issue340_$label: GAS carries '$want'"
}

# Shared expectations. The 507-space control is the last spelling the old fixed window covered, so it
# must be correct on both compilers; the annotated and struct-field shapes are unchanged on both.
run_case control_507   "$work/control_507.al"   42
run_case annotated_600 "$work/annotated_600.al" 42
run_case field_600     "$work/field_600.al"     104

if [ "$mode" = parent ]; then
  run_case boundary_508 "$work/boundary_508.al" 100
  run_case far_2000     "$work/far_2000.al"     100
  run_case bytes_600    "$work/bytes_600.al"    101
  run_case call_600     "$work/call_600.al"     102
  assert_load "$work/boundary_508.al" 'movq (%rax), %rax' 'movzbq (%rax), %rax' parent_boundary_508
  echo 'ok   issue340: parent loses the byte pointee one space past the old window'
else
  run_case boundary_508 "$work/boundary_508.al" 42
  run_case far_2000     "$work/far_2000.al"     42
  run_case bytes_600    "$work/bytes_600.al"    42
  run_case call_600     "$work/call_600.al"     42
  assert_load "$work/boundary_508.al" 'movzbq (%rax), %rax' 'movq (%rax), %rax' boundary_508
  assert_load "$work/control_507.al"  'movzbq (%rax), %rax' 'movq (%rax), %rax' control_507
  echo 'ok   issue340: the byte pointee survives arbitrary declaration whitespace'
fi
