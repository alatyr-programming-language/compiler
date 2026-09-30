## e2e / issue #768 — a field read through the payload pointer of a matched `Option(ptr(S))`.
##
## `Option(ptr(S))` is niche-folded to one word, and a `Some(p)` arm binds `p` to that word. The binding
## was an UNTYPED scalar, so `deref(p).f` and `n := deref(p); n.f` had no pointee to resolve and read 0
## — `check` and `build` both exit 0, a silent wrong value. `p` now binds as the `ptr(S)` it is, in every
## match form the lowering has: a statement `match`, a `match` used as a value, a tail `match` that is the
## function's result, and a `match` over a parameter. On the parent this returns 22 from the first check.
##
## 42 means every read held. Each miss owns its own code from 100 up.
Node := struct { v : u64, w : u64, next : Option(ptr(mut Node)) }

none_n := fn() -> Option(ptr(mut Node)) { Option(ptr(mut Node)).None }
some_n := fn(p : ptr(mut Node)) -> Option(ptr(mut Node)) { Option(ptr(mut Node)).Some(p) }

## tail match: the arm value is the function's result
tail_v := fn(h : Option(ptr(mut Node))) -> u64 {
  match h {
    Option::Some(p) => { deref(p).v + deref(p).w }
    Option::None => { 7 }
  }
}

main := fn() -> u64 {
  mut c := Node(v = 20, w = 2, next = none_n())
  h := some_n(ptr(c))
  ## statement match, the field read directly through the payload
  mut s : u64 = 0
  match h {
    Option::Some(p) => { s = deref(p).v + deref(p).w }
    Option::None => { s = 99 }
  }
  if s != 22 { return 100 + s }
  ## statement match, the pointee copied to a local first
  mut t : u64 = 0
  match h {
    Option::Some(p) => { n := deref(p); t = n.v + n.w }
    Option::None => { t = 99 }
  }
  if t != 22 { return 120 + t }
  ## match as a value
  u := match h { Option::Some(p) => { deref(p).v } Option::None => { 7 } }
  if u != 20 { return 150 + u }
  ## tail match over a parameter, both variants
  if tail_v(h) != 22 { return 180 }
  if tail_v(c.next) != 7 { return 181 }
  ## an enum-free struct field reached two hops away
  mut b := Node(v = 0, w = 0, next = some_n(ptr(c)))
  match b.next {
    Option::Some(p) => { if deref(p).w != 2 { return 190 } }
    Option::None => { return 191 }
  }
  return s + u
}
