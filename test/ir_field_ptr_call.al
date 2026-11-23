## #1863 (c): `deref(g(…)).f` — a scalar field read through the pointer a direct call returns. The call is
## built once (`bump` counts its calls), then the field is read as through a pointer name: from a struct
## laid out whole (`C`), and from the word prefix of one that is not (`R`, with an array of
## `Option(ptr(u8))`). `main` calls `lgm` (nine arguments, which the shared IR does not pass), so it stays
## legacy and builds the values the IR reads.
lgm := fn(a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64, h : u64, i : u64) -> u64 { a }
C := struct { n : u64, k : u8 }
R := struct { a : u64, f : bool, os : [Option(ptr(u8)); 2], z : u64 }
bump := fn(p : ptr(mut C)) -> ptr(mut C) {
  p.n = p.n + 1
  p
}
gr := fn(p : ptr(R)) -> ptr(R) { p }
## IR
cn := fn(p : ptr(mut C)) -> u64 { deref(bump(p)).n }
ck := fn(p : ptr(mut C)) -> u8 { deref(bump(p)).k }
ra := fn(p : ptr(R)) -> u64 {
  mut r : u64 = deref(gr(p)).a
  if deref(gr(p)).f { r = r + 100 }
  r
}
main := fn() -> u64 {
  if lgm(0, 0, 0, 0, 0, 0, 0, 0, 0) != 0 { return 99 }
  mut c := C(n = 10, k = 5)
  if cn(ptr(mut c)) != 11 { return 1 }
  if c.n != 11 { return 2 }
  if ck(ptr(mut c)) != 5 { return 3 }
  if c.n != 12 { return 4 }
  n := Option(ptr(u8)).None
  r := R(a = 6, f = true, os = [n, n], z = 1)
  if ra(ptr(r)) != 106 { return 5 }
  42
}
## expect: run 42
