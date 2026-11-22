## e2e — #1861: `bytes(s)` is the `[u8]` view of the underlying bytes of the `str` `s` (Stdlib appendix
## §3.6; Types §7), the same `{ptr, len}` pair with no copy. The shared IR builds it where the compiler's
## own src/ writes it: bound to an unannotated local over a raw `str_at` view, over a `str` parameter
## (a view local's object, copied when bound), over a literal, and passed to a `Slice(u8)` parameter. Each
## function here is asserted Built by its `scripts/e2e.sh` row, not only run.
## 3 + (10 + 20 + 4) + 3 + 2 = 42.
## expect: run 42
count_in := fn(s : str, c : u8) -> u64 {
  b := bytes(s)
  mut k : u64 = 0
  mut i : usize = 0
  while i < b.len {
    if b[i] == c { k = k + 1 }
    i = i + 1
  }
  k
}

sum_of := fn(v : Slice(u8)) -> u64 {
  mut t : u64 = 0
  for x in v { t = t + u64(x) }
  t
}

raw_sum := fn(p : ptr(u8), n : usize) -> u64 {
  rb := bytes(unchecked str_at(p, n))
  sum_of(rb) + u64(rb.len)
}

lit_len := fn() -> u64 {
  g := bytes("hi")
  u64(g.len)
}

main := fn() -> u64 {
  w : [u8; 3] = [10, 20, 4]
  p := ptr(w[0])
  count_in("((a(", 40) + raw_sum(p, 3) + lit_len()
}
