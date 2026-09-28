## Issue #716 — the same one-word slot as `issue716_const_str_field_local`, read back through an alias
## (`w := v`) instead of a call. The parent built this and ran it to 37: the alias copied the one
## reserved word and read a length of 0. Once the slot is sized from the resolved field it runs to 42.
App := struct { name : str, n : u64 }
APP := App(name = "hello", n = 7)
main := fn() -> u64 {
  v := APP.name
  w := v
  return w.len + 37
}
