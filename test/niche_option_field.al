## e2e — §8 `@niche`: a NICHE-FOLDED `Option(ptr(T))` as a STRUCT FIELD. The `o` field is ONE pointer
## word (None=0, Some(p)=p) at offset 0; `tag` follows at word 1. Exercises the field READ/MATCH path
## (`try_field_enum_scrut` folded branch): `match s.o` must dispatch on the null niche (Some ⟺ nonzero,
## None ⟺ zero) and bind `Some(p)` to the field word itself. A wrong field layout OR a wrong folded
## dispatch corrupts the sum, so the checks below (pointer round-trip via deref + `tag` correctness for
## BOTH the Some and None struct) pin it down. Returns 42.
S := struct { o : Option(ptr(u64)), tag : u64 }
main := fn() -> u64 {
  mut x : u64 = 42
  s : S = S(o = Option.Some(ptr(x)), tag = 100)
  ## Some(p) in a field: the bound pointer round-trips through deref
  mut got : u64 = 0
  match s.o { Option::Some(p) => { got = deref(p) } Option::None => { got = 7 } }
  if got != 42 { return 1 }
  ## the following field reads right (folded `o` occupies exactly one word)
  if s.tag != 100 { return 2 }
  ## None in a field: takes the None arm; its own `tag` still reads right
  n : S = S(o = Option.None, tag = 200)
  mut nt : u64 = 0
  match n.o { Option::Some(p) => { nt = 5 } Option::None => { nt = 9 } }
  if nt != 9 { return 3 }
  if n.tag != 200 { return 4 }
  return got
}
