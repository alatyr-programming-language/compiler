## e2e — Issue #299. The legal-control half of `test/reject_brand_module_array_element_sink.al`, and
## the reason its assertions are SPLIT across two scopes.
##
## At MODULE scope this file asserts COMPILATION ONLY: `G : [2]A = [A(1), A(2)]` is a legal array of
## a brand and the tag-7 element walker must accept it. Without this control the reject fixture
## beside it would pass just as well on a compiler that crudely refused every module-level array
## annotation, so this row is what makes that one mean "refuses the CROSSING" rather than "refuses
## the shape".
##
## The VALUE is asserted on a LOCAL instead, and the asymmetry is deliberate rather than an
## oversight — do not "fix" it. #674 records that a module-level array whose element type is a BRAND
## reads back all-zero today, with or without `mut`, while the identical array as a local is
## correct, and while a module-level array of `u64`, of an enum, or a `mut` array of a struct is
## correct. Asserting `u64(G[0]) + u64(G[1]) == 3` beside the module declaration would freeze that
## defect into this fixture: the row would pass today for the wrong reason and go red later, when
## #674 is FIXED, for a reason that has nothing to do with brand identity. So the module scope proves
## "the legal form is accepted" and the local proves "and the value path is right". When #674 lands,
## the module half can be tightened to assert the value too.
##
## RUNS to its value on x86_64 only. The three non-x86 backends implement a scalar core that does not
## lower a brand construction at all, so every brand-declaring program in this tree already traps
## loudly there; `test/accept_brand_unrefused_sinks.al` records that pre-existing backend-subset
## limit in full.
A := brand(u64)

G : [2]A = [A(1), A(2)]

main := fn() -> u64 {
  g : [2]A = [A(1), A(2)]
  if u64(g[0]) + u64(g[1]) != 3 { return 1 }
  return 42
}
