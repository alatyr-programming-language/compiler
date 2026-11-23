## #1863 (a): a scalar field read through a pointer to a struct the shared IR does not lay out whole — it
## has an array of `Option(ptr(u8))` and an array of structs, as `LCtx` does — when the field sits in the
## struct's WORD PREFIX: every field up to it is a one-word scalar or an array of 8-byte scalars, so its
## offset is the same whatever the later children's layout is. `main` and the setters call `lgm` (nine
## arguments, which the shared IR does not pass), so they stay legacy: the struct is built by legacy
## code and read by the IR. `rz` reads a field after the unproven children and stays legacy.
lgm := fn(a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64, h : u64, i : u64) -> u64 { a }
In := struct { x : u64, y : u64 }
P := struct { a : u64, f : bool, k : u8, ws : [u64; 3], b : i64, os : [Option(ptr(u8)); 4], ins : [In; 2], z : u64 }
## IR: prefix fields through a pointer parameter, by name and through `deref`, narrow ones included
rd := fn(p : ptr(P)) -> u64 {
  mut r : u64 = p.a + u64(p.k)
  if p.f { r = r + 100 }
  r
}
rb := fn(p : ptr(P)) -> i64 { deref(p).b }
rk := fn(p : ptr(P)) -> u8 { deref(p).k }
## legacy: past the first unproven child
rz := fn(p : ptr(P)) -> u64 { p.z }
set := fn(p : ptr(mut P), k : u8, b : i64) {
  if lgm(0, 0, 0, 0, 0, 0, 0, 0, 0) != 0 { return }
  p.k = k
  p.b = b
  p.f = false
}
main := fn() -> u64 {
  if lgm(0, 0, 0, 0, 0, 0, 0, 0, 0) != 0 { return 99 }
  n := Option(ptr(u8)).None
  mut s := P(a = 7, f = true, k = 200, ws = [u64(1), u64(2), u64(3)], b = -5, os = [n, n, n, n],
    ins = [In(x = 1, y = 2), In(x = 3, y = 4)], z = 9)
  if rd(ptr(s)) != 307 { return 1 }
  if rb(ptr(s)) != -5 { return 2 }
  if rk(ptr(s)) != 200 { return 3 }
  if rz(ptr(s)) != 9 { return 4 }
  set(ptr(mut s), 3, -8)
  if rd(ptr(s)) != 10 { return 5 }
  if rb(ptr(s)) != -8 { return 6 }
  if rk(ptr(s)) != 3 { return 7 }
  if s.ws[2] != 3 or s.z != 9 { return 8 }
  42
}
## expect: run 42
