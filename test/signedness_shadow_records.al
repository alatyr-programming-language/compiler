## e2e — a later `for` variable and a later payload binding shadow an earlier local of the same name
## (Declarations §6.1), and sema's records must follow the innermost one. The checker used to keep the
## FIRST `i` / `v` in its local list, so the second loop's `u64` counter and the second match's `u64`
## payload were typed as the first ones' `i64`, and the signed/unsigned refusal (Types §4.2/§4.3)
## fired on a well-typed program. 36 + 0 + 6 = 42 on every backend.
E := enum { A(i64), B(u64) }
pick := fn(n : u64) -> E {
  if n == 0 { return E.A(0 - 3) }
  E.B(n)
}
main := fn() -> u64 {
  mut c : i64 = 0
  for i in 0..3 { c = c + i }
  mut acc : u64 = 0
  for i in 0..u64(4) { acc = acc + i }
  match pick(0) { E::A(v) => { c = c + v }; E::B(v) => { c = c + 100 } }
  match pick(30) { E::A(v) => { acc = acc + 100 }; E::B(v) => { acc = acc + v } }
  acc + u64(c) + 6
}
