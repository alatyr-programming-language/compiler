## e2e (#1182 review) — `for p in xs` over a struct-element fixed-array PARAMETER `xs : [P; N]`. It
## has no `Slice` annotation, so it keeps the by-value element read it had before #1182; the PR's first
## head moved it onto the double-deref path of a `Slice(P)` parameter, and it crashed (SIGSEGV, 139).
## The due exit is 42. Until #1287 x86_64 trapped (132): the loop took its length from a frame word the
## parameter does not own. #1287 reads the element pointer by value and bounds the loop by the static N.
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
## expect: run 42
