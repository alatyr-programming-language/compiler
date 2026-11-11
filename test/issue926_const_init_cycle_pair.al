## e2e / issue #926 — a MUTUAL cycle among module-level comptime initializers is refused too.
##
## Declarations §7.1 makes "a cycle among comptime initializers" a compile error, and does not restrict
## that to a self-reference: `A := B + 1` / `B := A + 1` has no dependency order either, because each
## initializer's value depends on the other's. Both spellings crash the same way — the backend chases
## `A` into `B` into `A` — and both are measured on `58a80376` (omen, native x86_64): `check` rc 0,
## `build` **rc 139 SIGSEGV**.
##
## The refusal lands on the first declaration of the cycle in source order, `A`, at line 15.
##
## The chase enters each module-level const at most once per checked declaration, so it terminates and
## finds a cycle of any length (`issue926_const_init_cycle_long`); a legal chain of any depth is
## unaffected — see `issue926_const_chain_ok`. Only a real cycle is refused, so a refusal is certain.
##
A := B + 1
B := A + 1

main := fn() -> u64 {
  return A
}
## expect: reject "COMPTIME INITIALIZER CYCLE" "at line 15"
