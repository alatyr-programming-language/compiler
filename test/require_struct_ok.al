## §8.1 aggregate validity contract — a named struct underlying type is layout-identical to its
## require alias, while the predicate receives an ordinary by-value copy through the aggregate ABI.
Pair := struct { lo : u64, hi : u64 }
within := fn(p : Pair) -> bool { return p.lo != 0 }
consume := fn(p : Pair) -> u64 { return p.hi - p.lo }

Checked := Pair.require(within)
CheckedPrefix := @require(within) Pair
make_checked := fn() -> Checked { return Checked(Pair(lo = 4, hi = 9)) }

main := fn() -> u64 {
  x := Checked(Pair(lo = 2, hi = 7))
  if x.lo != 2 { return 1 }
  if x.hi != 7 { return 2 }
  y := make_checked()
  if y.lo != 4 { return 3 }
  if y.hi != 9 { return 4 }
  ## The second constructor is passed directly as an aggregate argument. Its preserved value must not
  ## alias the predicate's temporary copy, and the UFCS/prefix spellings must agree.
  return consume(CheckedPrefix(Pair(lo = 10, hi = 20)))
}
