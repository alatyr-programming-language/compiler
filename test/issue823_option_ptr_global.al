## e2e / issue #823 — a module-level `mut` global of type `Option(ptr(T))`.
##
## `Option(ptr(T))` is one folded word (None = 0, Some(p) = p). A `mut` global of that type took its
## layout from its initializer, and the bare `Option.None` names no type argument: the global became a
## two-word `[disc, payload]` over a bare `Option`, whose payload lost its pointee, so a matched `Some`
## read 0 through `deref(q).v` on a clean build. The declared type now decides: the global is one word
## in `.data`, and its store, its read, a `match` on it and a hand-off as an argument all use the fold.
##
## 42 means every read held. Each miss owns its own code from 100 up.
N := struct { v : u64, next : Option(ptr(mut N)) }
mut GB : Option(ptr(mut N)) = Option.None
mut GT : Option(ptr(mut N)) = Option(ptr(mut N)).None
mut C : u64 = 40
mut GC : Option(ptr(mut u64)) = Option.None

val := fn(o : Option(ptr(mut N))) -> u64 { match o { Some(q) => { return deref(q).v }; None => { return 0 } }; 0 }
set := fn(q : ptr(mut N)) { GB = Option(ptr(mut N)).Some(q) }

main := fn() -> u64 {
  mut b := N(v = 40, next = Option.None)
  mut c := N(v = 2, next = Option.None)
  ## None at start, statement match and a hand-off
  match GB { Some(_q) => { return 100 }; None => {} }
  if val(GB) != 0 { return 101 }
  ## a store from another function (typed head), then every read form
  set(ptr(mut b))
  if val(GB) != 40 { return 102 }
  match GB { Some(q) => { if deref(q).v != 40 { return 103 } }; None => { return 104 } }
  r := match GB { Some(q) => { deref(q).v }; None => { 105 } }
  if r != 40 { return 106 }
  o := GB
  if val(o) != 40 { return 107 }
  ## a store of None, then of a local
  GB = Option.None
  match GB { Some(_q) => { return 108 }; None => {} }
  loc : Option(ptr(mut N)) = Option.Some(ptr(mut c))
  GB = loc
  if val(GB) != 2 { return 109 }
  ## a typed-head initializer, and a pointer to a scalar global
  match GT { Some(_q) => { return 110 }; None => {} }
  GC = Option.Some(ptr(mut C))
  match GC { Some(p) => { deref(p) = deref(p) + val(GB) }; None => { return 111 } }
  C
}
