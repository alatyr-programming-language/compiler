## e2e / issue #926 — a qualified reference to ANOTHER module's same-named const is not a cycle.
##
## Declarations §7.1 refuses a cycle among comptime initializers, and a cycle is a property of
## BINDINGS: `m::X` names `m`'s `X` (Modules §2), a different binding from this module's `X`, so
## `X : u64 = m::X + 1` has a dependency order (`m::X`, then `X`) and is valid. Its value is 2.
##
## The first revision of the #926 check compared NAMES and refused it as "COMPTIME INITIALIZER
## CYCLE: `X` reaches back to itself", a false diagnostic. The check now resolves each reference to
## its declaration from the module that spells it, as name resolution does.
##
## The `module` directives are load-bearing: the two `X`s must live in two modules.
module m
pub X : u64 = 1

module issue926_const_qualified_same_name_ok
X : u64 = m::X + 1

main := fn() -> u64 {
  return X
}
## expect: run 2
