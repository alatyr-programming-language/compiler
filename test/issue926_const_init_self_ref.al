## e2e / issue #926 — a module-level const whose initializer names ITSELF is refused, not chased.
##
## Declarations §7.1: a module-level data binding's initializer MUST be compile-time-known, comptime
## initializers are evaluated in DEPENDENCY order, and "a **cycle** among comptime initializers is a
## compile error". `A := A + 1` is the cycle of length one: there is no order in which to evaluate it.
##
## Before the fix `check` answered rc 0 and the x86_64 backend died: `lower::global_init_value`
## resolved the `Var` through `module_const_value` and recursed into the initializer with no cycle
## guard — `global_init_value(Var A)` -> `A + 1` -> `global_init_value(Bin(+, Var A, 1))` ->
## `global_init_value(Var A)` -> … — until the stack was exhausted. Measured on `58a80376` (omen,
## native x86_64): `check` rc 0, `build` **rc 139 SIGSEGV**, no diagnostic. The same program with the
## const never read builds rc 0, which is what localised it to the path that EVALUATES the value.
##
## The refusal is located at the DECLARATION, which is where the author breaks the cycle.
A := A + 1

main := fn() -> u64 {
  return A
}
## expect: reject "COMPTIME INITIALIZER CYCLE" "at line 15"
