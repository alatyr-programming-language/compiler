#!/usr/bin/env bash
set -eu
set -o pipefail

: "${ALATYR:?ALATYR must name the compiler under test}"
mode="${1:-fixed}"
case "$mode" in
  fixed|parent) ;;
  *) echo "usage: $0 [fixed|parent]" >&2; exit 2 ;;
esac

work="$(mktemp -d "${TMPDIR:-/tmp}/alatyr-issue342.XXXXXX")"
trap 'rm -rf "$work"' EXIT

boundary_gap="$(printf '%*s' 502 '')"

write_fixture() {
  local path="$1" kind="$2" gap="$3"
  {
    printf '%s\n' \
      'Pt := struct { x : u64, y : u64 }' \
      ''
    if [ "$kind" = name ]; then
      printf 'sum := fn(s%s: Slice(Pt)) -> u64 {\n' "$gap"
    else
      printf 'sum := fn(s :%sSlice(Pt)) -> u64 {\n' "$gap"
    fi
    printf '%s\n' \
      '  return s[0].x + s[1].y' \
      '}' \
      '' \
      'main := fn() -> u64 {' \
      '  ps := [Pt(x = 10, y = 32), Pt(x = 1, y = 32)]' \
      '  return sum(ps[0..2])' \
      '}'
  } > "$path"
}

name_short="$work/name_short.al"
type_short="$work/type_short.al"
name_boundary="$work/name_boundary.al"
type_boundary="$work/type_boundary.al"
write_fixture "$name_short" name ''
write_fixture "$type_short" type ' '
write_fixture "$name_boundary" name "$boundary_gap"
write_fixture "$type_boundary" type "$boundary_gap"

fail_case() {
  echo "FAIL $*" >&2
  exit 1
}

check_accept() {
  local name="$1" source="$2" err="$work/$1.check.err"
  if ! "$ALATYR" check "$source" > /dev/null 2> "$err"; then
    fail_case "$name: check rejected the valid source: $(<"$err")"
  fi
  echo "ok   $name: check accepted"
}

run_x86() {
  local name="$1" source="$2" out="$work/$1.out" err="$work/$1.err" got
  check_accept "$name" "$source"
  if ! "$ALATYR" -o "$out" "$source" > /dev/null 2> "$err"; then
    fail_case "$name: build rejected: $(<"$err")"
  fi
  if "$out" > /dev/null 2>&1; then got=0; else got=$?; fi
  [ "$got" = 42 ] || fail_case "$name: got $got want 42"
  echo "ok   $name: build/run 42"
}

expect_x86_parent_reject() {
  local name="$1" source="$2" out="$work/$1.out" err="$work/$1.err"
  check_accept "$name" "$source"
  if "$ALATYR" -o "$out" "$source" > /dev/null 2> "$err"; then
    fail_case "$name: parent unexpectedly built the boundary source"
  fi
  grep -qF 'mixed-kind tuple PARAM field access not yet supported' "$err" \
    || fail_case "$name: parent rejected with an unexpected diagnostic: $(<"$err")"
  echo "ok   $name: parent build rejected at the old recovery boundary"
}

run_a64() {
  local name="$1" source="$2" gas="$work/$1.a64.s" obj="$work/$1.a64.o" elf="$work/$1.a64" got
  "$ALATYR" aarch64 "$source" > "$gas" 2> "$work/$1.a64.err" \
    || fail_case "$name(a64): emit"
  aarch64-unknown-linux-gnu-as "$gas" -o "$obj" 2> "$work/$1.a64.as.err" \
    || fail_case "$name(a64): assemble"
  aarch64-unknown-linux-gnu-ld "$obj" -o "$elf" 2> "$work/$1.a64.ld.err" \
    || fail_case "$name(a64): link"
  if qemu-aarch64 "$elf" > /dev/null 2>&1; then got=0; else got=$?; fi
  [ "$got" = 42 ] || fail_case "$name(a64): got $got want 42"
  echo "ok   $name(a64): build/run 42"
}

run_rv64() {
  local name="$1" source="$2" gas="$work/$1.rv64.s" obj="$work/$1.rv64.o" elf="$work/$1.rv64" got
  "$ALATYR" riscv64 "$source" > "$gas" 2> "$work/$1.rv64.err" \
    || fail_case "$name(rv64): emit"
  riscv64-unknown-linux-gnu-as "$gas" -o "$obj" 2> "$work/$1.rv64.as.err" \
    || fail_case "$name(rv64): assemble"
  riscv64-unknown-linux-gnu-ld "$obj" -o "$elf" 2> "$work/$1.rv64.ld.err" \
    || fail_case "$name(rv64): link"
  if qemu-riscv64 "$elf" > /dev/null 2>&1; then got=0; else got=$?; fi
  [ "$got" = 42 ] || fail_case "$name(rv64): got $got want 42"
  echo "ok   $name(rv64): build/run 42"
}

run_wat() {
  local name="$1" source="$2" wat="$work/$1.wat" wasm="$work/$1.wasm" got
  "$ALATYR" wat "$source" > "$wat" 2> "$work/$1.wat.err" \
    || fail_case "$name(wat): emit"
  wat2wasm "$wat" -o "$wasm" 2> "$work/$1.wat2wasm.err" \
    || fail_case "$name(wat): assemble"
  if wasmtime "$wasm" > /dev/null 2>&1; then got=0; else got=$?; fi
  [ "$got" = 42 ] || fail_case "$name(wat): got $got want 42"
  echo "ok   $name(wat): build/run 42"
}

expect_fail_loud_emit() {
  local name="$1" backend="$2" source="$3" needle="$4" gas="$work/$1.$2"
  "$ALATYR" "$backend" "$source" > "$gas" 2> "$work/$1.$2.err" \
    || fail_case "$name($backend): emit"
  grep -qF "$needle" "$gas" \
    || fail_case "$name($backend): unsupported aggregate path was not fail-loud"
  echo "ok   $name($backend): boundary remains fail-loud"
}

if [ "$mode" = parent ]; then
  run_x86 issue342_name_short "$name_short"
  run_x86 issue342_type_short "$type_short"
  expect_x86_parent_reject issue342_name_boundary "$name_boundary"
  expect_x86_parent_reject issue342_type_boundary "$type_boundary"
else
  run_x86 issue342_name_short "$name_short"
  run_x86 issue342_type_short "$type_short"
  run_x86 issue342_name_boundary "$name_boundary"
  run_x86 issue342_type_boundary "$type_boundary"
fi

run_a64 issue342_name_short "$name_short"
run_rv64 issue342_name_short "$name_short"
run_wat issue342_name_short "$name_short"
run_a64 issue342_type_short "$type_short"
run_rv64 issue342_type_short "$type_short"
run_wat issue342_type_short "$type_short"

expect_fail_loud_emit issue342_name_boundary aarch64 "$name_boundary" 'brk #0'
expect_fail_loud_emit issue342_name_boundary riscv64 "$name_boundary" 'ebreak'
expect_fail_loud_emit issue342_name_boundary wat "$name_boundary" '(unreachable)'
expect_fail_loud_emit issue342_type_boundary aarch64 "$type_boundary" 'brk #0'
expect_fail_loud_emit issue342_type_boundary riscv64 "$type_boundary" 'ebreak'
expect_fail_loud_emit issue342_type_boundary wat "$type_boundary" '(unreachable)'
