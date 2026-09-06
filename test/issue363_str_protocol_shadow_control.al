## e2e CONTROL — Issue #363 / Modules §3 + Stdlib appendix §2.4: publishing a base-library name
## widens who may NAME it; it must not change which declaration a call site RESOLVES to. This
## fixture is deliberately GREEN ON THE PARENT TOO (61ca2c2) — that is what makes it a control. It
## answers 42 before and after the `pub` markers, so a resolution change would show up as a wrong
## value here rather than as a rejection somewhere else.
##
## Three same-spelling collisions with the base library are exercised at once, with `base::str`
## pulled into the same compilation by the qualified `base::str::chars`:
##   * `iter`  — this file's own overload keyed on `Ticks`, versus `base::str`'s on `CharIter`
##               and `SplitIter`;
##   * `next`  — same, and it is what the `for` desugar (Control Flow §6) must select;
##   * `split` — a user function whose spelling matches the base library's `pub split`, but whose
##               signature and meaning are this file's.
## Every rejection code is distinct and < 126.

Ticks := struct { n : u64 }

iter := fn(t : Ticks) -> Ticks { Ticks(n = t.n) }

next := fn(in out t : Ticks) -> Option(u64) {
  if t.n >= 3 { return Option(u64).None }
  v := t.n
  t.n = t.n + 1
  Option(u64).Some(v * 10)
}

split := fn(n : u64) -> u64 { n / 2 }

main := fn() -> u64 {
  ## the base library is in this compilation, through the §3.6 entry point
  s := "Aé"
  mut cursor : CharIter = base::str::chars(s)
  if cursor.len != 3 { return 1 }

  ## the user's `iter` wins for the user's type
  mut t := Ticks(n = 0)
  c := iter(t)
  if c.n != 0 { return 2 }

  ## the user's `next` wins, and yields the USER's values (10 * index), not code points
  a := unwrap(u64, next(t))
  if a != 0 { return 3 }
  b := unwrap(u64, next(t))
  if b != 10 { return 4 }
  if t.n != 2 { return 5 }

  ## the user's `split` wins over `base::str::split`, which takes `ptr(str)` and returns SplitIter
  if split(9) != 4 { return 6 }

  ## the `for` desugar drives the user's `next`: three yields, 0 + 10 + 20
  mut sum : u64 = 0
  mut k : u64 = 0
  mut u := Ticks(n = 0)
  for v in u {
    sum = sum + v
    k = k + 1
    if k > 3 { return 7 }
  }
  if k != 3 { return 8 }
  if sum != 30 { return 9 }

  42
}
