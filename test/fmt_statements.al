## fmt round-trip for the statement forms fmt previously fail-loud rejected: range- and
## iterable-`for`, `loop`/`break`/`continue`, `a[i] =`, `a[i].f =`, the nested-field `o.p.x =` store,
## and `deref(p) =`. No body comments (fmt retains only LEADING-decl comments, so the `##` count
## round-trips exactly). Builds + runs to 42; AllocWith and the `unchecked { }` block are covered by
## the reused alloc_with_elision / unchecked_block fmt tests.
P := struct { x : u64, y : u64 }
O := struct { p : P }
main := fn() -> u64 {
  mut r : u64 = 0
  for k in 0 .. 4 { r = r + k }
  if r != 6 { return 1 }
  xs : [u64; 3] = [10, 20, 12]
  mut s : u64 = 0
  for v in xs { s = s + v }
  if s != 42 { return 2 }
  mut j : u64 = 0
  mut lp : u64 = 0
  loop {
    j = j + 1
    if j == 2 { continue }
    if j > 5 { break }
    lp = lp + j
  }
  if lp != 13 { return 3 }
  mut arr : [u64; 3] = [1, 2, 3]
  arr[1] = 40
  if arr[1] != 40 { return 4 }
  mut pa : [P; 2] = [P(x = 1, y = 2), P(x = 3, y = 4)]
  pa[0].x = 7
  if pa[0].x != 7 { return 5 }
  mut o : O = O(p = P(x = 0, y = 0))
  o.p.x = 11
  if o.p.x != 11 { return 6 }
  mut z : u64 = 5
  zp := ptr(mut z)
  deref(zp) = 99
  if z != 99 { return 7 }
  return 42
}
