## Seed-forms registry entry `option_ptr_bare_some_arg` (scripts/seed_forms.tsv) — NOT a corpus fixture.
## #789: a BARE `Option.Some(x)` passed straight as an `Option(ptr(T))` argument, and the payload
## dereferenced in the callee. State `seed`: the tree folds it since #796 (#789 fixed); the 0.2.4 seed
## SIGSEGVs. Due: 42.
N := struct { v : u64, next : Option(ptr(mut N)) }
f := fn(h : Option(ptr(mut N))) -> u64 {
  match h {
    Option::Some(q) => { nd : N = deref(q) ; return nd.v }
    Option::None => { return 1 }
  }
  return 2
}
main := fn() -> u64 {
  mut c := N(v = 42, next = Option(ptr(mut N)).None)
  f(Option.Some(ptr(mut c)))
}
