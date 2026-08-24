## e2e — loop-as-expression break-value type consistency (Control Flow §7.2): the varian-break pair
## `break 1` (int, tag 1) and `break true` (bool, tag 2) are KNOWN incompatible types → `alatyr check`
## must REJECT (a bare `break` sibling with no value imposes no constraint and stays legal).
main := fn() -> u64 {
  mut k : u64 = 0
  z := loop {
    k = k + 1
    if k == 1 { break 1 }
    break true
  }
  return z + k
}
