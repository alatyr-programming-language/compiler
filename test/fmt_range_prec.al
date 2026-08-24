## P2-FMT-AST — the `alatyr fmt` AST formatter round-trips (a) scalar match RANGE arms and (b)
## precedence-forcing PARENTHESES. Both were silent formatter gaps: a half-open `lo..hi` / inclusive
## `lo..=hi` arm re-emitted as an EMPTY pattern (` => body`, unparseable), and a grouping paren
## `(a + b) * c` re-emitted as `a + b * c` (a DIFFERENT program — the parser erases surface parens).
## a = 10 (7 in [0,10)); b = 5 (10 excluded by [0,10), caught by [0,10]); c = (1 + 2) * 9 = 27 → 42.
main := fn() -> u64 {
  a := match 7 { 0..10 => 10, _ => 0 }
  b := match 10 { 0..10 => 99, 0..=10 => 5, _ => 0 }
  c := (1 + 2) * 9
  return a + b + c
}
