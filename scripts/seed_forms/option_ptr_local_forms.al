## Seed-forms registry entry `option_ptr_local_forms` (scripts/seed_forms.tsv) — NOT a corpus fixture.
## An `Option(ptr(T))` local initialized from a field read through a pointer and then re-assigned from
## a call, #775. The 0.2.4 seed sizes the local by its initializer form, so the two bindings disagree;
## the tree binds every form as the one folded word since #787. The tree compiler must return 42.
Node := struct { v : u64, next : Option(ptr(mut Node)) }
Holder := struct { k : u64, head : Option(ptr(mut Node)) }
none_n := fn() -> Option(ptr(mut Node)) { Option(ptr(mut Node)).None }
some_n := fn(p : ptr(mut Node)) -> Option(ptr(mut Node)) { Option(ptr(mut Node)).Some(p) }
node_some := fn(o : Option(ptr(mut Node))) -> bool { match o { Option::Some(_p) => { true } Option::None => { false } } }
forms := fn(hp : ptr(Holder)) -> u64 {
  mut hits : u64 = 0
  mut q := deref(hp).head
  if node_some(q) { hits += 40 }
  q = none_n()
  if node_some(q) { return 100 }
  hits + 2
}
main := fn() -> u64 {
  mut n := Node(v = 1, next = none_n())
  h := Holder(k = 0, head = some_n(ptr(n)))
  forms(ptr(h))
}
