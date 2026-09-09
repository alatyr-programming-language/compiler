P := struct { f : u64, keep : u64 }
same := fn(p : ptr(mut P)) -> ptr(mut P) { return p }
main := fn() -> u64 {
  mut s := P(f = 1, keep = 2)
  q := same(ptr(s))
  deref(same(ptr(s))).f = "text"
  return deref(q).f
}
