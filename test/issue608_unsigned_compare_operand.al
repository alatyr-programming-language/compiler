## #608 — an ordering whose operand is an unsigned value compares UNSIGNED, whatever shape the operand
## has: an `unchecked` binary expression, a struct field, a brand conversion, a parameter divided by 1,
## or literal-free arithmetic on a local (Types §3.2: signedness lives in the operation, chosen by the
## operand types). The signed mirrors stay signed. Each check returns its own code; 42 is a pass.
## Parent `8bacc85a` of #944 (x86_64, omen): built, and ran to 1 (the `(hi + 0) < 0` row) from both
## build-then-run and `alatyr run`.
## Each negated row is written `not (…)`: well-formed whichever way spec#144 settles how `not` binds
## against a comparison. Do not run `alatyr fmt` over this file; it strips those parentheses today.
S := struct {
  off : usize,
}

B := brand(u64)

g1 := fn(x : u64) -> u64 {
  x
}

div_param := fn(p3 : u64) -> u64 {
  if 1 > unchecked (p3 / 1) {
    return 1
  }
  42
}

seed38 := fn() -> u64 {
  p : u64 = 7
  if g1(1) > unchecked ((p | 255) - 300) {
    return 1
  }
  42
}

main := fn() -> u64 {
  hi : usize = 18446744073709551610
  if unchecked (hi + 0) < 0 {
    return 1
  }
  s := S(off = 18446744073709551610)
  if s.off < 0 {
    return 2
  }
  b : B = B(9223372036854775817)
  if not (255 < unchecked (u64(b) / 1)) {
    return 3
  }
  p : u64 = 7
  if not (unchecked (1 - p) > 1) {
    return 4
  }
  if div_param(18446744073709551614) != 42 {
    return 5
  }
  if seed38() != 42 {
    return 6
  }
  p2 : u64 = 2
  v6 : u64 = 6
  p300 : u64 = 300
  if not (100 < unchecked (1 - p2)) {
    return 7
  }
  if unchecked (1 - p) < 1 {
    return 8
  }
  if 1 > unchecked (p2 - 255) {
    return 9
  }
  if not (1 <= unchecked (1 - p2)) {
    return 10
  }
  if not (2 <= unchecked (3 - v6)) {
    return 11
  }
  if not (unchecked (2 - v6) >= 10) {
    return 12
  }
  if not (unchecked (10 - p300) > 65535) {
    return 13
  }
  if not (1 < unchecked (1 - g1(255))) {
    return 14
  }
  if not (1 <= unchecked (p2 ^ 100)) {
    return 15
  }
  m : i64 = -6
  if not (unchecked (m + 0) < 0) {
    return 16
  }
  sm : i64 = -6
  if not (sm < 0) {
    return 17
  }
  42
}
## expect: run 42
