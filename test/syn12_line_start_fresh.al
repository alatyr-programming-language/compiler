## e2e — Grammar §2.6 continuing tokens (SYN-12, spec 1.12.0; #1910). The list of tokens that continue
## the previous line is closed, and `-` and `(` are not on it: `-` has a prefix form, `(` can begin a
## statement. So a line beginning with one of them is a NEW statement. The parser used to fold such a
## line into the one before: `return a` then `- 8` returned `a - 8`, and `a = a` then `(a + 2)` was the
## call `a(a + 2)`, which does not compile. The `[` probe is `syn12_line_start_bracket.al`, apart,
## because an array-literal statement is a fail-loud stub on aarch64, riscv64 and wasm (#1191).
## Controls: inside `( … )` newlines are free, so a `-` line there still subtracts, and `+` (no prefix
## form, a continuing token) still continues.
P := struct {
  a : u64
}

## `return a` then a line `- 8`: the return ends at the newline; the `-8` after it is unreachable.
ret_then_minus := fn() -> i64 {
  a : i64 = 50
  return a
    - 8
}

## A tail `a` then a line `- 8`: two statements, the block's value is `-8`.
tail_then_minus := fn() -> i64 {
  a : i64 = 50
  a
  - 8
}

## `a = a` then `-a` then `u64(a + 2)`: the `-a` is its own expression statement, `a` stays 40.
assign_then_minus := fn() -> u64 {
  mut a : i64 = 40
  a = a
  -a
  u64(a + 2)
}

## `a = a` then a line `(a + 2)`: the parenthesized line is the block's value, not a call of `a`.
assign_then_paren := fn(k : u64) -> u64 {
  mut a : u64 = k
  a = a
  (a + 2)
}

## `r = p.a` then a line `(r + 2)`: a field read, then the block's value, not a method call `p.a(…)`.
field_then_paren := fn(k : u64) -> u64 {
  p := P(a = k)
  mut r : u64 = 0
  r = p.a
  (r + 2)
}

## Controls. Inside parentheses the newline is free, so the `-` line subtracts.
paren_minus := fn() -> u64 {
  a : u64 = 50
  (a
    - 8)
}

## `+` is a continuing token: the line continues.
plus_line := fn() -> u64 {
  a : u64 = 40
  a
    + 2
}

main := fn() -> u64 {
  if ret_then_minus() != 50 { return 1 }
  if tail_then_minus() != -8 { return 2 }
  if assign_then_minus() != 42 { return 3 }
  if assign_then_paren(40) != 42 { return 4 }
  if field_then_paren(40) != 42 { return 5 }
  if paren_minus() != 42 { return 6 }
  if plus_line() != 42 { return 7 }
  42
}
## expect: run 42
