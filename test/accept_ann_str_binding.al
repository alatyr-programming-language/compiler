## The guard against a false reject: a `str` literal bound to a `str` annotation conforms and must
## stay ACCEPTED. `x : u8 = 7` / the widened `u8 -> u64` read exercise the untyped-literal-in-context
## (§3.4) and implicit-widen (§4.3) rules the new check must never touch.
main := fn() -> u64 {
  s : str = "ok"
  a : u8 = 7
  w : u64 = a
  return w + s.len()
}
