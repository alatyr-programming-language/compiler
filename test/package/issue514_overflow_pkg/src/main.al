## issue #514, second fault — a MANIFEST build reaching the overflow-policy family (Concurrency
## §6.3) by its bare specified spelling. The ambient trigger in `src/cli.al` sat under
## `is_pkg == false`, so on the parent compiler NO bare overflow op resolved in a package build for
## ANY of the four prefixes: `alatyr build package.al` answered `alatyr: check: unbound name at
## line 13 in main`, rc 1 — even for `wrapping_add`, which worked in a single-file program, and
## even when the result type was written out. §6.3 says the family is available EVERYWHERE (no
## grant) and a package module is a user program, so the gate is gone for this trigger only.
## This module deliberately never spells the family's result-type name, so nothing but the
## `checked_`/`wrapping_`/`saturating_`/`overflowing_` trigger can pull its prelude. Exit 42.
main := fn() -> u64 {
  a : u64 = 41
  s := checked_add(a, 1)
  if is_none(s) { return 1 }
  if unwrap(s) != 42 { return 2 }
  if wrapping_add(a, 1) != 42 { return 3 }
  if saturating_sub(a, 40) != 1 { return 4 }
  p := overflowing_add(a, 1)
  if p.0 != 42 { return 5 }
  if p.1 { return 6 }
  42
}
