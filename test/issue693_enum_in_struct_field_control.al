## e2e — issue #693 CONTROL 2: a struct field whose TYPE is an enum — the neighbouring class of
## #447 / #448 / #449 / #462 / #465 / #504, which is about an enum INSIDE a struct and not about an
## enum as the owner. The owner `s` is a struct and legitimately has members, one of which happens to
## hold an enum value; reading it and matching it must keep working exactly as before.
##
## 61 = 39 + 22: the enum member is matched for its payload, the plain member is read directly.
E := enum { A, B(u64, u64) }
S := struct { e : E, n : u64 }
main := fn() -> u64 {
  s := S(e = E.B(17, 22), n = 22)
  mut acc : u64 = 0
  match s.e {
    E.A => { acc = 1 }
    E.B(x, y) => { acc = x + y }
  }
  acc + s.n
}
