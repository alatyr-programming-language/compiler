## e2e reject — #1663: an `in` STRUCT parameter handed on as an `in out` argument. The parameter is an
## immutable binding (Memory §3.1, Functions §9 `in-param`), so the whole place it names is not writable
## whatever the struct's own fields say (§3.3); §2.3 refuses the argument. MEASURED on the parent
## (`836b97ba`, native x86_64): `check` rc 0, x86_64 ran 32 and x86_legacy 60 (#1637's missing copy).
## expect: reject "check: immutable binding" "at line 9"
S := struct { mut a : u64, b : u64 }
put := fn(in out s : S) { s.a = 30 }
go := fn(s : S) -> u64 {
  put(s)
  s.a
}
main := fn() -> u8 {
  mut v := S(a = 2, b = 10)
  r := go(v)
  u8(v.a + r)
}
