## Seed-forms registry entry `option_ptr_payload_field` (scripts/seed_forms.tsv) — NOT a corpus fixture.
## A field read straight through the payload of a matched `Option(ptr(S))` (`deref(p).v`), #768. The
## tree types the `Some(p)` binding as `ptr(S)` since #787; the 0.2.4 seed binds an untyped scalar
## and reads 0. The tree compiler must return 42.
Node := struct { v : u64, w : u64 }
some_n := fn(p : ptr(mut Node)) -> Option(ptr(mut Node)) { Option(ptr(mut Node)).Some(p) }
main := fn() -> u64 {
  mut c := Node(v = 40, w = 2)
  h := some_n(ptr(c))
  mut s : u64 = 0
  match h {
    Option::Some(p) => { s = deref(p).v + deref(p).w }
    Option::None => { s = 99 }
  }
  s
}
