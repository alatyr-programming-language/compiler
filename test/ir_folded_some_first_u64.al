## e2e — #1711: a Some-FIRST `Option` over a NON-pointer (`Option(u64)`) is NOT niche-folded (Types
## §6.2: `u64` provides no niche) and keeps the ordinary tag + payload layout, `Some` at discriminant
## 0. Accepting the folded shape in either variant order must not reach it: a parameter, a result, a
## local and a `match` in each arm order, with a payload of 0 (which a folded reading would take for
## the absent case) and a non-zero one, across IR-built functions.
## 42 when every check held; otherwise the failed check's own code, 101 upward.
Option := fn(T : type) -> type { return enum { Some(T), None } }
mk := fn(v : u64, z : u64) -> Option(u64) {
  if z == 0 { return Option(u64).None }
  Option(u64).Some(v)
}
rd := fn(o : Option(u64)) -> u64 {
  match o { Some(v) => v + 1; None => 7 }
}
rd_none_first := fn(o : Option(u64)) -> u64 {
  match o { None => 7; Some(v) => v + 1 }
}
main := fn() -> u64 {
  if rd(mk(0, 1)) != 1 { return 101 }
  if rd(mk(40, 1)) != 41 { return 102 }
  if rd(mk(40, 0)) != 7 { return 103 }
  z : Option(u64) = mk(0, 1)
  if rd_none_first(z) != 1 { return 104 }
  n : Option(u64) = Option(u64).None
  if rd_none_first(n) != 7 { return 105 }
  return 42
}
