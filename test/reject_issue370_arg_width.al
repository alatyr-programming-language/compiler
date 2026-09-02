## Issue #370 / Types §4.4 — the equal-width contract holds in ARGUMENT position too. A two-word
## source reinterpreted as a three-word target has no equal-width reading, so the build must refuse
## with the located diagnostic rather than pass two words to a callee that reads three. The
## companion `accept`/`run` row proves the equal-width case is emitted correctly; this row proves the
## unequal one is not silently emitted. On the parent this program BUILT (the argument had no
## aggregate arm at all) and the resulting binary ran to a wrong exit.
A2 := struct { a : u64, b : u64 }
B3 := struct { x : u64, y : u64, z : u64 }

take3 := fn(b : B3) -> u64 {
  if b.x != 5 { return 101 }
  if b.y != 6 { return 102 }
  if b.z != 7 { return 103 }
  return 0
}

main := fn() -> u64 {
  a2 := A2(a = 5, b = 6)
  return take3(unchecked bitcast(B3, a2))
}
