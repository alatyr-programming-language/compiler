## e2e / issue #775 — an `Option(ptr(T))` LOCAL is one word however it is initialized.
##
## The lowering sized a local by the FORM of its initializer: one word from a call, `1 + payload` words
## from a field, a parameter or a variant literal, and an untyped scalar word from `deref(p).f`. So a
## same-typed re-assignment across two forms was refused ("already bound … by a NARROWER binding"),
## and the untyped word was handed to a by-reference Option parameter as if it were the block address —
## a SIGSEGV. The same happened to a folded value passed straight as an argument (`f(none())`,
## `f(deref(hp).head)`). Every form now binds, assigns and passes the same one folded word.
##
## 42 means every walk and every hand-off held. Each miss owns its own code from 100 up.
Node := struct { v : u64, next : Option(ptr(mut Node)) }
Holder := struct { k : u64, head : Option(ptr(mut Node)) }

none_n := fn() -> Option(ptr(mut Node)) { Option(ptr(mut Node)).None }
some_n := fn(p : ptr(mut Node)) -> Option(ptr(mut Node)) { Option(ptr(mut Node)).Some(p) }
node_some := fn(o : Option(ptr(mut Node))) -> bool { match o { Option::Some(_p) => { true } Option::None => { false } } }
node_at := fn(o : Option(ptr(mut Node))) -> ptr(mut Node) { match o { Option::Some(p) => { p } Option::None => { panic("node_at on None") } } }

## a list walk: the local starts from a parameter and is re-assigned from a field read
walk := fn(head : Option(ptr(mut Node))) -> u64 {
  mut s : u64 = 0
  mut cur := head
  while node_some(cur) {
    n := deref(node_at(cur))
    s = s + n.v
    cur = n.next
  }
  s
}

## every initializer form, each re-assigned from every other form
forms := fn(h : Holder, hp : ptr(Holder), o : Option(ptr(mut Node))) -> u64 {
  mut hits : u64 = 0
  mut r := none_n()
  r = h.head
  if node_some(r) { hits += 1 }
  mut q := deref(hp).head
  if node_some(q) { hits += 1 }
  q = none_n()
  if node_some(q) { return 100 }
  q = o
  if node_some(q) { hits += 1 }
  mut w := Option(ptr(mut Node)).None
  w = deref(hp).head
  if node_some(w) { hits += 1 }
  mut x := o
  x = Option(ptr(mut Node)).None
  if node_some(x) { return 101 }
  x = deref(node_at(o)).next
  if node_some(x) { hits += 1 }
  hits
}

main := fn() -> u64 {
  mut c := Node(v = 20, next = none_n())
  mut b := Node(v = 1, next = some_n(ptr(c)))
  mut a := Node(v = 0, next = some_n(ptr(b)))
  h := Holder(k = 5, head = some_n(ptr(a)))
  hp := ptr(h)
  e := Holder(k = 6, head = none_n())
  ## folded values passed straight as arguments, one per form
  if walk(some_n(ptr(a))) != 21 { return 110 }
  if walk(deref(hp).head) != 21 { return 111 }
  if walk(h.head) != 21 { return 112 }
  if walk(none_n()) != 0 { return 113 }
  if walk(Option(ptr(mut Node)).None) != 0 { return 114 }
  if walk(deref(ptr(e)).head) != 0 { return 115 }
  if walk(a.next) != 21 { return 116 }
  ## a local bound from `deref(p).f`, then passed on
  r := deref(hp).head
  if walk(r) != 21 { return 117 }
  f := forms(h, hp, a.next)
  if f != 5 { return 120 + f }
  return 21 + walk(r)
}
