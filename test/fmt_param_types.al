## §5 fmt — the PARAMETER surface. `Param` records a parameter's type as the bare HEAD token of an
## applied type (`ptr(mut R)` → `ptr`, `Slice(u64)` → `Slice`, `[u64; 2]` → the ELEMENT `u64`,
## `fn(u64) -> E` → `fn`) and ERASES the passing-mode modifier and the default, because every pass
## downstream re-reads them from source. fmt re-emitted the recorded spans, so a reformat silently
## changed the program: `p : ptr(mut R)` came back as `p : ptr` (test/deref_field_write ran 42 before
## the reformat and 0 after), an `in out` parameter became by-value, and a fn-value parameter lost its
## signature (test/fn_value_enum_ret: 42 → 211). Every piece is now recovered by source-scan off the
## parameter NAME. Each step contributes 6: 6 * 7 = 42.
E := enum {
  A(u64),
  B(u64),
}

R := struct {
  a : u64,
  b : u64,
}

mk := fn(x : u64) -> E {
  return E.A(x)
}

viaptr := fn(p : ptr(mut R)) -> u64 {
  return deref(p).a
}

viaslice := fn(s : Slice(u64)) -> u64 {
  return u64(s.len) + s[0]
}

viaarr := fn(xs : [u64; 2]) -> u64 {
  return xs[0] + xs[1]
}

viafn := fn(f : fn(u64) -> E, v : u64) -> u64 {
  mut o : u64 = 0
  match f(v) {
    E::A(n) => { o = n }
    E::B(n) => { o = 100 }
  }
  return o
}

setsix := fn(in out y : u64) {
  y = 6
}

outsix := fn(out z : u64) {
  z = 6
}

withdef := fn(a : u64, b : u64 = 4) -> u64 {
  return a + b
}

main := fn() -> u64 {
  mut r := R(a = 6, b = 0)
  ys := [1, 2, 3, 4, 5]
  mut m : u64 = 0
  mut n : u64 = 0
  setsix(m)
  outsix(n)
  return viaptr(ptr(mut r)) + viaslice(ys[0..5]) + viaarr([2, 4]) + viafn(mk, 6) + m + n + withdef(2)
}
