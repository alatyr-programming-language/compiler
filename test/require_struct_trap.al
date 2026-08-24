## §8.1 aggregate validity contract — a failing predicate traps at the explicit require construction.
Pair := struct { lo : u64, hi : u64 }
within := fn(p : Pair) -> bool { return p.lo != 0 }
Checked := Pair.require(within)

main := fn() -> u64 {
  x := Checked(Pair(lo = 0, hi = 2))
  return 42
}
