## Seed-forms registry entry `option_ptr_bare_none_reassign` (scripts/seed_forms.tsv) — NOT a corpus
## fixture. #789 shape e: a BARE `Option.None` re-assigned to an annotated `Option(ptr(T))` local inside
## a `loop`. State `tree`: the tree compiler refuses it ("already bound … by a NARROWER binding", the
## #775 sizing class) while the 0.2.4 seed answers 42 — a tree regression relative to the seed. The
## spelled-out `Option(ptr(mut N)).None` is accepted by both. Due: 42 (one pass, 1 + 41).
N := struct { v : u64, next : Option(ptr(mut N)) }
f := fn(h : Option(ptr(mut N))) -> u64 {
  mut p : Option(ptr(mut N)) = h
  mut s : u64 = 0
  loop {
    match p {
      Option::Some(q) => { s = s + 1 ; p = Option.None }
      Option::None => { break }
    }
  }
  s + 41
}
main := fn() -> u64 {
  mut c := N(v = 42, next = Option(ptr(mut N)).None)
  f(Option(ptr(mut N)).Some(ptr(mut c)))
}
