## Seed-forms registry entry `option_ptr_param_match` (scripts/seed_forms.tsv) — NOT a corpus fixture.
## #789 shape b, constructors SPELLED OUT: `match` an `Option(ptr(T))` PARAMETER and dereference the
## payload. The 0.2.4 seed SIGSEGVs; the tree answers 42 (the BARE `Option.Some(x)` argument
## is row `option_ptr_bare_some_arg`).
## Due: 42.
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
  f(Option(ptr(mut N)).Some(ptr(mut c)))
}
