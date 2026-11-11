## #766 — a `u64` ordering whose operand is an `if` or `match` expression, or literal-only `unchecked`
## arithmetic, compares UNSIGNED (Types §3.2: the operation follows the operand types; Control Flow §4
## and §5: an `if`/`match` expression has its arms' type). A value at or above 2^63 is a large unsigned
## value, never a negative one. Each check returns its own code; 42 is a pass.
## Parent `8bacc85a` of #944 (x86_64, omen): built, and ran to 1 (the `match` operand row) from both
## build-then-run and `alatyr run`; each row except the bound control (6) also failed written alone.
## Each negated row is written `not (…)`: well-formed whichever way spec#144 settles how `not` binds
## against a comparison. Do not run `alatyr fmt` over this file; it strips those parentheses today.
E := enum {
  A(u64),
  B,
}

P4 := struct {
  k2 : u64,
}

g1 := fn(x : u64) -> u64 {
  x
}

f := fn(x : u64) -> Result(u64, u64) {
  Result(u64, u64).Ok(x)
}

main := fn() -> u64 {
  big : u64 = 9223372036854775808
  e := E.A(9223372036854775808)
  if not (match e { E::A(x) => x, E::B => 0 } > 1) {
    return 1
  }
  p : u64 = 3
  if not (if p == 3 { big } else { p } >= p) {
    return 2
  }
  one : u64 = 1
  if not (unchecked (1 - 2) >= one) {
    return 3
  }
  if not (unchecked (1 - 2) >= g1(1)) {
    return 4
  }
  if 1 > unchecked (if p == 3 { p } else { 1 } * g1(9223372036854775808)) {
    return 5
  }
  v : u64 = if p == 3 { big } else { p }
  if not (v >= p) {
    return 6
  }
  if not (match f(big) { Result::Ok(w) => w, Result::Err(r) => 0 } > 1) {
    return 7
  }
  q : u64 = 7
  mut d : u64 = 1
  d = unchecked (1 - q)
  if not (d >= if q == 0 { 1000 } else { 1 }) {
    return 8
  }
  p4 := P4(k2 = 5)
  if p4.k2 > unchecked (0 - 100) {
    return 9
  }
  42
}
## expect: run 42
