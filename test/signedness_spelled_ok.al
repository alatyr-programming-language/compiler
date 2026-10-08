## e2e — the spelled forms Types §4.2/§4.3 and §9.1 accept where a signed and an unsigned value meet:
## the binding annotated with the type it is used as, the constructor form `T(v)` on one operand, a
## range whose bound is constructed (`0..u64(4)`), and a literal operand, which takes its partner's
## type (§2.3). 6 + 20 + 6 + 10 = 42 on every backend.
main := fn() -> u64 {
  xs : [u64; 3] = [1, 2, 3]
  s := xs[0..3]
  mut acc : u64 = 0
  mut i : usize = 0
  while i < s.len { acc = acc + s[i]; i = i + 1 }
  k : i64 = 0 - 4
  n : usize = 24
  if k < i64(n) { acc = acc + u64(i64(n) + k) }
  mut r : u64 = 0
  for j in 0..u64(4) { r = r + j }
  acc = acc + r
  acc + 10
}
