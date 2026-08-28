## e2e — the public Option helpers must honor the one-word niche layout of Option(ptr(T)).
## Exercise Some and None through is_some, is_none, unwrap, unwrap_or, and get. The ordinary
## `Option(u64).Some(1)` case is explicit too: a representation test must not mistake a payload value
## of 1 for the ordinary `Some` discriminant.
main := fn() -> u64 {
  mut value : u64 = 42
  mut fallback : u64 = 7
  some : Option(ptr(u64)) = Option(ptr(u64)).Some(ptr(value))
  none : Option(ptr(u64)) = Option(ptr(u64)).None

  if not Option::is_some(ptr(u64), some) { return 1 }
  if Option::is_none(ptr(u64), some) { return 2 }
  if Option::is_some(ptr(u64), none) { return 3 }
  if not Option::is_none(ptr(u64), none) { return 4 }

  sp := Option::unwrap(ptr(u64), some)
  if deref(sp) != 42 { return 5 }
  ep := Option::expect(ptr(u64), some, "unexpected None")
  if deref(ep) != 42 { return 6 }

  so := Option::unwrap_or(ptr(u64), some, ptr(fallback))
  if deref(so) != 42 { return 7 }
  no := Option::unwrap_or(ptr(u64), none, ptr(fallback))
  if deref(no) != 7 { return 8 }

  sg := Option::get(ptr(u64), ptr(some))
  match sg {
    Option::Some(p) => { if deref(deref(p)) != 42 { return 9 } }
    Option::None => { return 10 }
  }
  ng := Option::get(ptr(u64), ptr(none))
  match ng {
    Option::Some(_) => { return 11 }
    Option::None => {}
  }

  ordinary : Option(u64) = Option(u64).Some(1)
  if not Option::is_some(u64, ordinary) { return 12 }
  if Option::is_none(u64, ordinary) { return 13 }
  ov := Option::unwrap(u64, ordinary)
  if ov != 1 { return 14 }
  og := Option::get(u64, ptr(ordinary))
  match og {
    Option::Some(p) => { if deref(p) != 1 { return 15 } }
    Option::None => { return 16 }
  }

  ordinary_str : Option(str) = Option(str).Some("ok")
  text := Option::unwrap(str, ordinary_str)
  if not (text == "ok") { return 17 }
  text_get := Option::get(str, ptr(ordinary_str))
  if not Option::is_some(ptr(str), text_get) { return 18 }
  return 42
}
