## #1688: a struct literal with a niche-folded `Option(ptr(T))` field, returned by value. The folded
## field is one pointer word (Types §6.2, Memory §4.2); x86_64's legacy emitter pushed a `$0`
## placeholder for its `Some(p)`, so the caller read `None` (100 for 42).
P := struct { p : Option(ptr(u64)), tag : u64 }
mk := fn(x : ptr(u64)) -> P { P(p = Option(ptr(u64)).Some(x), tag = 42) }
main := fn() -> u8 {
  v : u64 = 7
  r := mk(ptr(v))
  mut got : u64 = 0
  match r.p {
    Some(q) => { got = deref(q) }
    None => { got = 0 }
  }
  if got == 7 and r.tag == 42 { return 42 }
  u8(got + 100)
}
## expect(x86_64): run 42
