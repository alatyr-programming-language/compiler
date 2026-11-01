## e2e — issue #703 control: the member accesses the refusal must leave alone — a struct field through
## a pointer (Types §6.1), a tuple position, a union member (§6.3), a slice view and a str length.
## It answers 21 = 5 + 4 + 9 + 2 + 1 on the parent and after.
P := struct { x : u64 }
U := union { m(u64), f(f64) }
main := fn() -> u64 {
  mut r := P(x = 5)
  p := ptr(mut r)
  t := (3, 4)
  u := U.m(9)
  a : [u64; 3] = [1, 2, 3]
  s := a[0..2]
  w : str = "k"
  p.x + u64(t.1) + u.m + u64(s.len) + u64(w.len)
}
## expect: run 21
