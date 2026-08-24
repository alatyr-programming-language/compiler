## e2e (I11 correct-or-trap) — the NARROW-RESERVATION collision must be REJECTED with a diagnostic,
## never written next door.
##
## Alatyr `:=` locals are FUNCTION-scoped, and the lower's slot map reuses a name's FIRST reservation
## (`bind_*_slot` no-ops on an already-bound name — deliberate, so a same-shape rebinding does not grow
## the frame). Binding `t` as a 1-word scalar and then rebinding the SAME name to a 3-word struct
## leaves the struct UNDER-RESERVED, and both ends then go wrong: the 3-register struct return is
## stored over the NEIGHBOURING locals' slots, and `t.x` addresses word 0 by the aggregate convention —
## one slot away from where the narrow store put it — so it reads a slot NOTHING ever wrote. That is
## stale STACK content, so the wrong value depends on the frame size of this function and of every
## caller above it: a frame-layout LOTTERY.
##
## This is exactly the defect that made `test/array_of_tuples` exit 1 instead of 42 while
## `scripts/fixpoint.sh` stayed GREEN — `emit_gas` bound `tbc` both as a `usize` match-scratch level
## and as a 3-word `TupleByteComponent`, so `tbc.ok` read a neighbour's stale slot and the `Index` arm
## took the standard-byte-tuple path for plain nested/array-of tuples. `src/` contains no
## mixed/array-of-tuple local, so the compiler could not see the bug in its own source.
##
## `require_reservation` (`src/lower.al`) rejects it at LOWERING — sema/`check` does not model slot
## reservation — so this fixture asserts the BUILD fails AND that it fails with the diagnostic. The
## needle matters: before the guard this same source made the compiler die of an internal overflow
## trap (SIGILL, no message), which a bare non-zero exit check would have accepted as "fail-loud".
P := struct { x : u64, y : u64, z : u64 }
mk3 := fn() -> P { P(x = 10, y = 11, z = 14) }
main := fn() -> u64 {
  mut n := 0
  if n == 0 {
    t := 7                ## `t` bound FIRST as a 1-word scalar
    n = n + t
  }
  if n == 7 {
    t := mk3()            ## the SAME function-scoped name, now a 3-word struct — under-reserved
    ## COMPARE rather than sum the fields: summing stale words trips the overflow trap, which would
    ## hide the point behind a loud accident. A comparison keeps the pre-guard outcome a wrong VALUE.
    if t.x == 10 { n = 42 } else { n = 1 }
  }
  n
}
