## e2e (#1182) — an ANNOTATED struct-element slice view local, `xs : Slice(P) = t[0..2]`, is the same
## program as the inferred `xs := t[0..2]` (Types `Slice(T)`; Control Flow §5.4): its slot holds the
## {data, len} pair itself. x86_64 used to take any annotated name for a parameter, whose slot holds a
## POINTER to the caller's pair, so an element read dereferenced the data pointer once more and
## crashed (SIGSEGV, exit 139). Each check returns its own code; 42 is a pass. The parameter rows keep
## the by-reference read honest: a `Slice(P)` parameter still reads through its pointer.
P := struct { a : u64, b : u64 }

## a `Slice(P)` parameter: still read through its pointer to the caller's pair
via_param := fn(s : Slice(P)) -> u64 {
  mut n : u64 = 0
  for p in s { n = n * 10 + p.b }
  n + s[1].a - s[0].a + s.len
}

main := fn() -> u64 {
  t : [P; 2] = [P(a = 1, b = 2), P(a = 3, b = 4)]
  xs : Slice(P) = t[0..2]
  ## the issue's first row: an indexed field read
  if xs[0].b * 10 + xs[1].b != 24 { return 1 }
  ## the issue's second row: `for` over the annotated local
  mut n : u64 = 0
  for p in xs { n = n * 10 + p.b }
  if n != 24 { return 2 }
  if xs.len != 2 { return 3 }
  ## a whole-element copy out of the view
  e := xs[1]
  if e.a != 3 { return 4 }
  ## the annotated local passed on to a parameter: 24 + 3 - 1 + 2
  if via_param(xs) != 28 { return 5 }
  ## a sub-range of the annotated local
  zs : Slice(P) = xs[1..2]
  if zs.len != 1 or zs[0].b != 4 { return 6 }
  42
}
## expect: run 42
