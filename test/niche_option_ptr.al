## e2e — §8 `@niche`: `Option(ptr(T))` is a NICHE-FOLDED enum (Types §6.2/§8, Memory §4.2): it is
## exactly pointer-width, with NO discriminant word — `None` = null (0), `Some(p)` = the pointer `p`,
## and a `match` tests `word == 0` for `None`. Verifies the folded size (== 8), a `Some(p)` round-trip
## through `deref`, and the `None` ≡ null case. Returns 42.
main := fn() -> u64 {
  ## folded layout: exactly one pointer word (no discriminant)
  if size(Option(ptr(u64))) != 8 { return 1 }
  ## Some(p) round-trips: construct, match, deref the bound pointer
  mut x : u64 = 42
  s : Option(ptr(u64)) = Option.Some(ptr(x))
  mut got : u64 = 0
  match s { Option::Some(p) => { got = deref(p) } Option::None => { got = 7 } }
  if got != 42 { return 2 }
  ## None ≡ null: the absent case takes the None arm
  n : Option(ptr(u64)) = Option.None
  mut tag : u64 = 0
  match n { Option::Some(p) => { tag = 5 } Option::None => { tag = 9 } }
  if tag != 9 { return 3 }
  return got
}
