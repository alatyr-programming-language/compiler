## Seed-forms registry entry `option_ptr_mut_generic` (scripts/seed_forms.tsv) — NOT a corpus fixture.
## A generic instance over a `ptr(mut T)` type argument (`Option::is_some(ptr(mut Node), o)`), #770.
## The 0.2.4 seed spells the instance label with a space (`…ptr_mut Node`) and the assembler refuses
## the build; the tree maps every non-symbol byte to `_` since #787. The tree compiler must return 42.
Node := struct { v : u64, w : u64 }
main := fn() -> u64 {
  mut c := Node(v = 40, w = 2)
  o : Option(ptr(mut Node)) = Option(ptr(mut Node)).Some(ptr(c))
  if not Option::is_some(ptr(mut Node), o) { return 100 }
  n := Option::unwrap(ptr(mut Node), o)
  deref(n).v + deref(n).w
}
