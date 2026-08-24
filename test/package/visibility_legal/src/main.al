## `main` — a SIBLING of `geo`. Only `geo`'s `pub` surface is nameable here (§3), and it is named
## through every spelling this compiler supports today: a full `::` path to a function, a constant, a
## struct type, an enum type and a cross-module GENERIC; a listed member PROJECTION (§4.1.1) of a
## function, a type and an enum; a `pub` RE-EXPORT published by a descendant (§4.3); and the ambient
## stdlib, which is reached through the INJECTED ROOT rather than as a sibling of `main`.
##
## Two legal §4 spellings are deliberately absent because they do not work on this compiler yet, and
## both fail IDENTICALLY on the pre-check compiler (measured) — so this fixture does not silently
## encode them as illegal: a qualified UFCS call `p.geo::bump()` ("unbound name" at check), and a
## module ALIAS to a SUBMODULE (`gc := geo::child` then `gc::re_answer()`, an undefined symbol at ld).
## Projecting a `pub` cross-module CONSTANT (`(PUB_C) := geo`) is part of the legal surface too: the
## bare name below must be the comptime alias to `geo::PUB_C`, not a local slot or a module-global read.
(answer, Pt, Tag, tag_code, PUB_C) := geo
gc := geo::child

main := fn() -> u64 {
  ## FULL PATHS onto `pub` declarations: a function, a constant, a type + a fn taking it, a generic,
  ## an enum type + a fn over it, and a descendant's `pub` re-export.
  a := geo::answer()
  b := PUB_C
  p := geo::Pt(x = 1, y = 2)
  c := geo::bump(ptr(p))
  d := geo::widen(u64, 5)
  e := geo::tag_code(geo::Tag.hi)
  f := geo::child::from_ancestor()
  i := gc::re_answer()
  if i != a { return 1 }
  ## the LISTED MEMBER PROJECTION of a `pub` function, type and enum (§4.1.1)
  g := answer()
  q := Pt(x = 7, y = 0)
  h := tag_code(Tag.hi)
  ## the ambient stdlib, through the injected root
  std::io::print("visibility_legal\n")
  return a + b + c + d + e + f + g + q.x + h
}
