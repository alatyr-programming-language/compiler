## e2e (#1211) — a call that returns `Slice(T)` with a struct, enum or `str` element is iterated
## like any other slice view (Types `Slice(T)`; Control Flow §5.4): bound first (`xs := pass(…)`)
## or iterated directly (`for s in pass(…)`). x86_64 bound `xs` as a nominal two-word struct (the
## lib declares `Slice`), and a non-var iterable knew its element only for `str`, so the loop var
## was one scalar word at an 8-byte stride: the struct rows read 0 and the bound `str` row read 1.
## Each check returns its own code; 42 is a pass.
P := struct { a : u64, b : u64 }
E := enum { A(u64), B(u64, u64) }

pass := fn(s : Slice(P)) -> Slice(P) { s }
passe := fn(s : Slice(E)) -> Slice(E) { s }
passs := fn(t : Slice(str)) -> Slice(str) { t }
gpass := fn(T : type, s : Slice(T)) -> Slice(T) { s }

ev := fn(e : E) -> u64 {
  match e {
    E::A(x) => { x }
    E::B(x, y) => { x * 10 + y }
  }
}

main := fn() -> u64 {
  t : [P; 2] = [P(a = 1, b = 2), P(a = 3, b = 4)]
  ## the issue row: a bound call result, then iterated
  xs := pass(t[0..2])
  mut n : u64 = 0
  for p in xs { n = n * 10 + p.b }
  if n != 24 { return 1 }
  if xs.len != 2 or xs[1].a != 3 { return 2 }
  ## iterated directly
  n = 0
  for p in pass(t[0..2]) { n = n * 10 + p.a }
  if n != 13 { return 3 }
  ## a one-element sub-range, the issue first row (due 123 = a 1, b 23)
  u : [P; 1] = [P(a = 1, b = 23)]
  n = 0
  for p in pass(u[0..1]) { n = n + p.a * 100 + p.b }
  if n != 123 { return 4 }
  ## enum elements, bound and direct
  es : [E; 2] = [E.A(7), E.B(1, 2)]
  ys := passe(es[0..2])
  n = 0
  for e in ys { n = n * 100 + ev(e) }
  if n != 712 { return 5 }
  n = 0
  for e in passe(es[0..2]) { n = n * 100 + ev(e) }
  if n != 712 { return 6 }
  ## str elements, bound (the issue comment row: due 32)
  ss : [str; 2] = ["abc", "de"]
  r := passs(ss[0..2])
  n = 0
  for s in r { n = n * 10 + u64(s.len) }
  if n != 32 { return 7 }
  ## a generic `-> Slice(T)` at a struct element, bound and direct
  gs := gpass(P, t[0..2])
  n = 0
  for p in gs { n = n * 10 + p.b }
  if n != 24 { return 8 }
  n = 0
  for p in gpass(P, t[0..2]) { n = n * 10 + p.b }
  if n != 24 { return 9 }
  42
}
## expect: run 42
