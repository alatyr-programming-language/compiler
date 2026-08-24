## Well-formed (spec Memory §5.3.1 permitted flow): `p := ptr(x)` binds a scoped reference into the SAME
## scope and reads through it — NOT an escape. The check must accept and it runs to 42 (40 + 2).
use_ref := fn() -> u64 {
  x := 40
  p := ptr(x)
  return deref(p) + 2
}
main := fn() -> u64 { return use_ref() }
