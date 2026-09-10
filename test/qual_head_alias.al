## Issue #580, closed-set witness — BIT 2, a local ALIAS, in BOTH of the parser's two shapes.
##
## `m := std::math` is the shape `parser.al`'s module-alias branch recognises: it fires only when
## the right-hand side carries a `::`, and records the path in the decl's `ret` span.
##
## `Opt := Option` is the other one, and it is the shape #580 measured as the sharpest false reject.
## A BARE right-hand side never reaches that branch at all, so it is stored as an ordinary kind-0
## value binding whose value is a variable, and the head has to be followed one hop to the module or
## type it names. That is what `src/driver.al:2499` (`strbuf := rt`) and `src/driver.al:43`
## (`ifc := iface`) are — 219 call sites in `src/` alone — which is why the self-host build is this
## arm's real regression test and this fixture is its registered miniature.
##
## Both heads have a kind mask of exactly 4.
m := std::math
Opt := Option

main := fn() -> u64 {
  o : Option(u64) = Option(u64).Some(60)
  v := Opt::unwrap(u64, o)
  if m::floor(4.9) == 4.0 { return v + 4 }
  return 1
}
