## e2e / issue #824 — a module-level array global of `Option(ptr(T))`.
##
## `[Option(ptr(T)); N]` is N folded words (None = 0, Some(p) = p). A global array took its element type
## from its first initializer element, and the bare `Option.None` names no type argument: each element
## became a two-word `[disc, payload]` over a bare `Option`, whose payload lost its pointee, so a matched
## `Some` element read 0 on a clean build, and `check` refused an element in a value position as an
## "ENUM-element ARRAY GLOBAL". The declared element type now decides: one word per element in `.data`,
## element stores and reads, and a direct `match` on an element — the shape a match-binding stack takes.
##
## 42 means every element held. Each miss owns its own code from 100 up.
N := struct { v : u64, next : Option(ptr(mut N)) }
mut GS : [Option(ptr(mut N)); 4] = [Option.None; 4]
mut DEPTH : usize = 0

val := fn(o : Option(ptr(mut N))) -> u64 { match o { Some(q) => { return deref(q).v }; None => { return 0 } }; 0 }
push := fn(q : ptr(mut N)) { GS[DEPTH] = Option.Some(q); DEPTH = DEPTH + 1 }
pop := fn() { DEPTH = DEPTH - 1; GS[DEPTH] = Option.None }

main := fn() -> u64 {
  mut b := N(v = 30, next = Option.None)
  mut c := N(v = 12, next = Option.None)
  match GS[3] { Some(_q) => { return 100 }; None => {} }
  push(ptr(mut b))
  push(ptr(mut c))
  ## an element read into an annotated and an unannotated local
  o : Option(ptr(mut N)) = GS[0]
  x := GS[1]
  if val(o) + val(x) != 42 { return 101 }
  ## a direct match in statement and value position
  match GS[0] { Some(q) => { if deref(q).v != 30 { return 102 } }; None => { return 103 } }
  r := match GS[1] { Some(q) => { deref(q).v }; None => { 104 } }
  if r != 12 { return 105 }
  ## the untouched elements are still None
  mut nnone : u64 = 0
  mut i : usize = 0
  while i < 4 { e : Option(ptr(mut N)) = GS[i]; match e { Some(_q) => {}; None => { nnone = nnone + 1 } }; i = i + 1 }
  if nnone != 2 { return 106 }
  ## a store of None through the stack discipline, then a typed-head store
  pop()
  match GS[1] { Some(_q) => { return 107 }; None => {} }
  GS[3] = Option(ptr(mut N)).Some(ptr(mut c))
  val(GS[0]) + val(GS[3])
}
