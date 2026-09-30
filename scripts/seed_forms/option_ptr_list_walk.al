## Seed-forms registry entry `option_ptr_list_walk` (scripts/seed_forms.tsv) — NOT a corpus fixture.
## The idiomatic list walk strict_forms.md §1 asks for: an `Option(ptr(T))` local re-assigned from each
## node's `next` inside a `loop` over a `match`, constructors spelled out (#789 shape o1). The 0.2.4
## seed SIGSEGVs; the tree answers 42 (10 + 32). This entry is what keeps `src/` on the transitional
## null spelling until a promotion.
N := struct { v : u64, next : Option(ptr(mut N)) }
sum := fn(h : Option(ptr(mut N))) -> u64 {
  mut p : Option(ptr(mut N)) = h
  mut s : u64 = 0
  loop {
    match p {
      Option::Some(q) => { nd : N = deref(q) ; s = s + nd.v ; p = nd.next }
      Option::None => { break }
    }
  }
  s
}
main := fn() -> u64 {
  mut c := N(v = 32, next = Option(ptr(mut N)).None)
  mut b := N(v = 10, next = Option(ptr(mut N)).Some(ptr(mut c)))
  sum(Option(ptr(mut N)).Some(ptr(mut b)))
}
