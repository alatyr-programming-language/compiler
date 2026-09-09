P := struct { f : u64, flag : bool }
main := fn() -> u64 {
  mut s := P(f = 1, flag = false)
  p : ptr(mut P) = ptr(s)
  deref(p).f = 40
  deref(p).flag = true
  return deref(p).f + if deref(p).flag { 2 } else { 0 }
}
