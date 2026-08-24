## §8.1 aggregate validity contract — an unchecked grant removes the predicate path but preserves the
## complete aggregate value and its fields.
Pair := struct { lo : u64, hi : u64 }
within := fn(p : Pair) -> bool { return p.lo != 0 }
Checked := @require(within) Pair

main := fn() -> u64 {
  x := unchecked { Checked(Pair(lo = 42, hi = 1)) }
  return x.lo
}
