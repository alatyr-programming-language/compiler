## e2e — issue #1464 CONTROL: the six owner kinds the refusal must leave ALONE, one row each of the
## #703 item-3 owner-kind census that #1464 completes. A struct field and a struct field through a
## pointer (Types §6.1), a raw union member (§6.3, which REQUIRES this stays accepted), a slice view's,
## a fixed array's and a `str`'s length (§6.4/§7). It answers 135 = 42 + 42 + 42 + 3 + 3 + 3 on the
## parent and after; a fix that refuses any row here is over-broad.
P := struct { a : u64 }
U := union { m(u64), f(f64) }
same := fn(p : ptr(mut P)) -> ptr(mut P) { return p }
main := fn() -> u64 {
  mut p := P(a = 42)
  u := U.m(42)
  xs : [u64; 3] = [1, 2, 3]
  s := xs[0..3]
  w : str = "abc"
  p.a + u.m + deref(same(ptr(mut p))).a + u64(s.len) + u64(xs.len) + u64(w.len)
}
## expect: run 135
