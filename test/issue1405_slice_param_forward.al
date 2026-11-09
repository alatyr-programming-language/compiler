## e2e (#1405) — a struct/enum-element `Slice(P)` PARAMETER passed on to another call (Types §7: a
## `[T]` parameter holds the two-word pair itself; Functions §2.3: an `in` parameter is bound by the
## value argument). The parameter's slot holds a POINTER to the caller's {ptr, len} pair, but x86_64
## passed the ADDRESS of that slot, so the callee read the pointer as the data word and a stale frame
## word as the length: `twice` below answered len 48 (exit 88 from build-then-run, 232 from
## `alatyr run`). Each check returns its own code; 42 is a pass.
P := struct { a : u64, b : u64 }
E := enum { A(u64), B(u64) }

pass := fn(s : Slice(P)) -> Slice(P) { s }

## the issue's program: the forwarded parameter is bound from the call, then returned
twice := fn(s : Slice(P)) -> Slice(P) {
  r := pass(s)
  r
}

## the forwarded parameter read in the callee: len, indexed fields, and a `for`
sum_b := fn(s : Slice(P)) -> u64 {
  mut n : u64 = 0
  for p in s { n = n * 10 + p.b }
  n + s[0].a + s.len
}
fwd_sum := fn(s : Slice(P)) -> u64 { sum_b(s) }

## an enum element forwards the same way
count_b := fn(s : Slice(E)) -> u64 {
  mut n : u64 = 0
  for i in 0..s.len {
    match s[i] {
      E::A(v) => { n = n + v }
      E::B(v) => { n = n + 10 * v }
    }
  }
  n + s.len
}
fwd_count := fn(s : Slice(E)) -> u64 { count_b(s) }

main := fn() -> u64 {
  t : [P; 3] = [P(a = 1, b = 2), P(a = 3, b = 4), P(a = 5, b = 6)]
  ## the issue's row
  x := twice(t[0..3])
  if x.len != 3 { return 1 }
  ## a forwarded parameter read by the callee: 246 + 1 + 3
  if fwd_sum(t[0..3]) != 250 { return 2 }
  ## a sub-range view forwarded: 46 + 3 + 2
  if fwd_sum(t[1..3]) != 51 { return 3 }
  ## a view LOCAL still passes the address of its own pair
  v := t[0..3]
  if fwd_sum(v) != 250 { return 4 }
  y := twice(v)
  if y.len != 3 { return 5 }
  es : [E; 3] = [E.A(1), E.B(2), E.A(3)]
  ## 1 + 20 + 3 + 3
  if fwd_count(es[0..3]) != 27 { return 6 }
  42
}
## expect: run 42
