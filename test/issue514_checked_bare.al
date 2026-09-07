## issue #514 — the `checked_*` family (Concurrency §6.3, `lib/base/num.al`) reached by its BARE
## specified spelling from a single-file program. §6.3 makes the four overflow-policy prefixes
## "available everywhere (no grant)", but the ambient prelude trigger in `src/cli.al` listed only
## `wrapping_`/`saturating_`/`overflowing_` — the comment beside it named `checked_` and the code
## omitted it. A program whose only prelude need was `checked_*` therefore got NO base prelude and
## the parent compiler answered `alatyr: check: unbound name at line 21 in issue514_checked_bare`,
## rc 1. THIS FILE DELIBERATELY NEVER SPELLS THE FAMILY'S RESULT-TYPE NAME: writing it out tripped
## the neighbouring trigger and made the byte-identical program answer 42, which is exactly what
## hid the defect (the #393 class — a program's meaning depending on an incidental spelling
## elsewhere in the file). Do not "clarify" this fixture by naming that type; it would disarm it.
##
## Only `checked_add`/`checked_sub` are exercised: `checked_mul` needs the high-word helper, which
## has an x86_64/aarch64/riscv64 arm and no wasm arm, so its answer is arch-dependent for reasons
## that are not this issue. `test/overflow_policy.al` already covers the multiply on x86_64.
##
## Exit 42 when every arm reads back its specified value; each earlier code names one arm.
main := fn() -> u64 {
  a : u64 = 41
  mx : u64 = 18446744073709551615
  s := checked_add(a, 1)
  if is_none(s) { return 1 }
  if unwrap(s) != 42 { return 2 }
  n := checked_add(mx, 1)
  if is_some(n) { return 3 }
  if unwrap_or(n, 7) != 7 { return 4 }
  d := checked_sub(a, 40)
  if is_none(d) { return 5 }
  if unwrap(d) != 1 { return 6 }
  u := checked_sub(a, 42)
  if is_some(u) { return 7 }
  42
}
