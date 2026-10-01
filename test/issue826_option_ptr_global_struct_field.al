## e2e / issue #826 — a global struct with an `Option(ptr(T))` field before another field.
##
## A global's `.data` cells were laid out from its initializer's shape. The folded field's bare
## `Option.None` initializer was emitted as a two-word enum cell, while the field is one word, so every
## later field shifted by one word: `G.k` read the pad word. Each field cell is now sized by the field's
## declared type.
##
## 42 means every field held. Each miss owns its own code from 100 up.
N := struct { v : u64, next : Option(ptr(mut N)) }
H := struct { head : Option(ptr(mut N)), k : u64, tail : Option(ptr(mut N)), m : u64 }
mut G := H(head = Option.None, k = 30, tail = Option.None, m = 2)

main := fn() -> u64 {
  mut b := N(v = 10, next = Option.None)
  if G.k != 30 { return 100 }
  if G.m != 2 { return 101 }
  match G.head { Some(_q) => { return 102 }; None => {} }
  match G.tail { Some(_q) => { return 103 }; None => {} }
  G.head = Option.Some(ptr(mut b))
  G.tail = Option.Some(ptr(mut b))
  if G.k != 30 or G.m != 2 { return 104 }
  match G.head { Some(q) => { return G.k + G.m + deref(q).v }; None => { return 105 } }
  106
}
