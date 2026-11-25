## e2e — Grammar §2.6 continuing tokens (SYN-12, spec 1.12.0; #1910). The list of tokens that continue
## the previous line is closed, and `-`, `(` and `[` are not on it: `-` has a prefix form, `(` and `[`
## can begin a statement. So a line beginning with one of them is a NEW statement. The parser used to
## fold such a line into the one before (`return a` then `- 8` returned `a - 8`; `g` then `(42)` was a
## call; `v : [u64; 3] = xs` then `[0]` was `xs[0]`). Each probe returns its own code on the old
## reading, so the first wrong one names itself.
## Controls: inside `( … )` newlines are free, so a `-` line there still subtracts, and `+` (no prefix
## form, a continuing token) still continues.
g := fn(x : u64) -> u64 {
  x + 100
}

ident := fn(x : u64) -> u64 {
  x
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

## A tail `g` then a line `(42)`: the block's value is `42`, not the call `g(42)`.
tail_then_paren := fn() -> u64 {
  g
  (42)
}

## `h := g` then `(40)` then `h(2)`: `h` is `ident`, and the `(40)` line is a statement of its own.
bind_then_paren := fn() -> u64 {
  h := ident
  (40)
  h(2) + 40
}

## `v : [u64; 3] = xs` then a line `[0]`: `v` is the whole array, not the element `xs[0]`, and the
## `[0]` line is an array literal of its own.
bind_then_bracket := fn() -> u64 {
  xs : [u64; 3] = [7, 8, 9]
  v : [u64; 3] = xs
  [0]
  v[1] + 34
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
  if tail_then_paren() != 42 { return 4 }
  if bind_then_paren() != 42 { return 5 }
  if bind_then_bracket() != 42 { return 6 }
  if paren_minus() != 42 { return 7 }
  if plus_line() != 42 { return 8 }
  42
}
## expect: run 42
