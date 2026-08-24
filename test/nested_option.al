## Nested generic-enum values end-to-end: `Option(Option(u64))`.
## Exercises the three CALLER-side bugs the nested-generic enum payload used to hit:
##   (1) SIZING — `o := mko(...)` must copy all 3 return words (outer disc, inner disc, payload);
##   (2) DISPATCH — the INNER `match inner` (scrutinee `Option(u64)`, a parenthesized instance span)
##       must dispatch on the real discriminants, not fall to the integer path (both arms `$0`);
##   (3) AGG-ARG — a bound inner payload passed as a call arg (`unwrap(inner)`) must pass by-reference.
## All three now resolve the enum decl by its BASE name (stripping the `(…)` type-args). Returns 42.

unwrap := fn(o : Option(u64)) -> u64 {
  match o {
    Option::Some(v) => { return v }
    Option::None => { return 0 }
  }
}

mko := fn(v : u64) -> Option(Option(u64)) {
  Option(Option(u64)).Some(Option(u64).Some(v))
}

## bugs (1)+(2): nested inner match on the bound `inner : Option(u64)`
inner_match := fn(v : u64) -> u64 {
  o := mko(v)
  match o {
    Option::Some(inner) => {
      match inner {
        Option::Some(x) => { return x }
        Option::None => { return 0 }
      }
    }
    Option::None => { return 0 }
  }
}

## bugs (1)+(3): the bound `inner` passed as a by-reference aggregate call argument
helper_arg := fn(v : u64) -> u64 {
  o := mko(v)
  match o {
    Option::Some(inner) => { return unwrap(inner) }
    Option::None => { return 0 }
  }
}

main := fn() -> u64 {
  return inner_match(21) + helper_arg(21)
}
