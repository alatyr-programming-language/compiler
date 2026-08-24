## A nested-enum LITERAL bound with INFERRED type: `o := Option.Some(Option.Some(42))` — the outer
## constructor is BARE (no `Option(Option(u64)).Some(...)` annotation), so the local's slot type was
## recovered as the bare `Option`, losing the inner enum. That under-sized the slot AND made the outer
## `match o { Some(rr) => … }` bind `rr` as a SCALAR (its declared payload type is the un-substituted
## param `T`), so the INNER `match rr` dispatched on a garbage discriminant → the program returned 255.
## `collect_slots` now synthesizes the full instance type (`Option(Option(T))`) for a nested aggregate-
## literal payload, so the slot sizes right and `rr` binds as an enum. Returns 42.
main := fn() -> u64 {
  o := Option.Some(Option.Some(42))
  match o {
    Option::Some(rr) => {
      match rr {
        Option::Some(v) => { return v }
        Option::None => { return 1 }
      }
    }
    Option::None => { return 7 }
  }
}
