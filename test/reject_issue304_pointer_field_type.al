P := struct { f : u64, keep : u64 }
main := fn() -> u64 {
  mut s := P(f = 1, keep = 2)
  p : ptr(mut P) = ptr(s)
  deref(p).f = "text"
  return deref(p).f
}
