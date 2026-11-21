## #1688: as `issue1688_folded_field_return.al`, with the folded field second, so the fix is shown not
## to depend on the field's offset: the field's kind (a one-word enum) is what lost the pointer.
P := struct { tag : u64, p : Option(ptr(u64)) }
mk := fn(x : ptr(u64)) -> P { P(tag = 42, p = Option(ptr(u64)).Some(x)) }
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
