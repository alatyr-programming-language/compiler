## Seed-forms row `oneline_call_compound_if_in_while` (#1652, state `tree`): inside a `while`, a one-line
## `if c { <call statement>; j += 2 } else { <call statement>; j += 1 }` drops both increments, so the
## loop never advances (the guard stops it at 99). Due 42. Workaround: src/lower.al:fill_inferred_targs
## writes the `if`/`else` multi-line.
g := fn(p : ptr(mut u64), k : u64) -> u64 {
  deref(p) = deref(p) + k
  deref(p)
}
main := fn() -> u64 {
  mut n : u64 = 0
  mut j : usize = 0
  mut guard : u64 = 0
  while j < 10 {
    guard += 1
    if guard > 100 { return 99 }
    if j == 5 { g(ptr(n), 10); j += 2 } else { g(ptr(n), 1); j += 1 }
  }
  n + 24
}
