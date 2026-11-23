## e2e / issue #1466 — a bare-statement call that omits an `in out` argument is refused, located.
##
## Functions §5.1: `out` and `in out` parameters have no defaults, so a call that omits one supplies no
## result place and is ill-formed. This is the issue's own program, verbatim: the omitted `y` is the
## result place of a bare-statement call. #1822's fixtures (`test/issue1822_reject_*.al`) hold the
## sibling shapes (value position, forward reference, an omitted `in` parameter).
##
## NON-VACUOUS: at `aab6ce1a` (omen, native x86_64) it built with rc 0 and no diagnostic, and the
## program died with SIGSEGV (139) writing through the null place. At `dc9e18e2` the checker refuses
## it at the call and names the parameter.
g := fn(x : u64, in out y : usize) { y = x }
main := fn() -> u64 { g(7); 42 }
## expect: reject "leaves parameter `y` unbound: an `out` / `in out` parameter" "at line 12"
