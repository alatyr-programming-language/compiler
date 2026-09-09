P := struct { f : u64, flag : bool }
same := fn(p : ptr(mut P)) -> ptr(mut P) { return p }
main := fn() -> u64 {
  mut s := P(f = 1, flag = false)
  q := same(ptr(s))
  deref(same(ptr(s))).f = 40
  deref(same(ptr(s))).flag = true
  return deref(q).f + if deref(q).flag { 2 } else { 0 }
}
