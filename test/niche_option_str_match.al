## e2e — a folded `Option(ptr(str))` match must preserve the pointer's `str` pointee metadata.
## `Some(p)` is one pointer word, but `deref(p)` is still the two-word `str` view: check its `.len`
## and content, not only the selected arm. Direct Some/None, payload wildcard, a scalar-pointer payload,
## and an ordinary aggregate Option control the niche-specific binding path.
## Failure-first on current parent f98c62f: `seed/alatyr build` succeeds, but the produced program
## returns 11 (the first `deref(p).len` assertion fails) instead of the expected 42.
Pair := struct { len : u64, data : u64 }

main := fn() -> u64 {
  text := "ok"
  some : Option(ptr(str)) = Option(ptr(str)).Some(ptr(text))
  expr_len := match some {
    Option::Some(p) => deref(p).len,
    Option::None => 0
  }
  if expr_len != 2 { return 11 }

  match some {
    Option::Some(p) => {
      if deref(p).len != 2 { return 1 }
      if not (deref(p) == "ok") { return 2 }
    }
    Option::None => { return 3 }
  }

  none : Option(ptr(str)) = Option(ptr(str)).None
  match none {
    Option::Some(_) => { return 4 }
    Option::None => {}
  }

  wildcard : Option(ptr(str)) = Option(ptr(str)).Some(ptr(text))
  match wildcard {
    Option::Some(_) => {}
    _ => { return 5 }
  }

  mut value : u64 = 37
  scalar : Option(ptr(u64)) = Option(ptr(u64)).Some(ptr(value))
  match scalar {
    Option::Some(p) => { if deref(p) != 37 { return 6 } }
    Option::None => { return 7 }
  }

  aggregate : Option(Pair) = Option(Pair).Some(Pair(len = 2, data = 99))
  match aggregate {
    Option::Some(v) => {
      if v.len != 2 { return 8 }
      if v.data != 99 { return 9 }
    }
    Option::None => { return 10 }
  }
  return 42
}
