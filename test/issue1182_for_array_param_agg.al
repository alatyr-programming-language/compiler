## e2e (#1182 review) — `for p in xs` over a struct-element fixed-array PARAMETER `xs : [P; N]`. It
## has no `Slice` annotation, so it keeps the by-value element read it had before #1182; the PR's first
## head moved it onto the double-deref path of a `Slice(P)` parameter, and it crashed (SIGSEGV, 139).
## The due exit is 42. x86_64 traps (132) instead, the parent's behaviour: the loop takes its length
## from a frame word the parameter does not own, which is #1287 (`for` over a fixed-array parameter).
## When #1287 lands this row moves to 42. A trap is allowed here; a wrong value or a crash is not.
P := struct { a : u64, b : u64 }

sum := fn(xs : [P; 2]) -> u64 {
  mut n : u64 = 0
  for p in xs { n = n * 10 + p.b }
  n
}

main := fn() -> u64 {
  t : [P; 2] = [P(a = 1, b = 2), P(a = 3, b = 4)]
  if sum(t) != 24 { return 1 }
  42
}
## expect: trap
