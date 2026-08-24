## e2e reject (Memory §1 · OP-2): a compound assignment whose PLACE holds a CALL.
##
## Memory §1 is normative: `place ⊕= rhs` takes the place's address ONCE into a temporary, so a
## side-effecting place runs its effects EXACTLY once. Measured on the frozen seed, the textual
## rewrite this parser performs for a re-readable place is NOT equivalent here: `a[f()] = a[f()]
## + 1` calls `f` TWICE (CALLS = 2), while the spec requires ONE call. The parser has no way to
## bind the index into a fresh temporary, so the only outcome that is not a wrong value is a
## located reject (a trap is acceptable; a silently different number of side effects is not).
##
## Before the fix `a[f()] += 1` compiled CLEAN and ran `f` once but dropped the store entirely
## (measured: CALLS = 1, a[1] unchanged) — a silent wrong value, I11.
##
## Expected: rejected with the located diagnostic naming the re-readable-place requirement.
mut CALLS : u64 = 0
f := fn() -> u64 {
  CALLS += 1
  return 1
}
main := fn() -> u64 {
  mut a : [u64; 3] = [10, 20, 30]
  a[f()] += 1
  return CALLS * 100 + a[1]
}
