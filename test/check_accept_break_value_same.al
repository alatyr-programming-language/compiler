## e2e — loop-as-expression break-value type-consistency GUARD (Control Flow §7.2): two same-type
## (`int`) break exits are a COMMON-TYPE ACCEPT — `alatyr check` must keep this program accepted.
## (The build path is covered by loop_expr_labels.al.)
main := fn() -> u64 {
  mut k : u64 = 0
  z := loop {
    k = k + 1
    if k == 1 { break 100 }
    break 200
  }
  z - 100 + k - 1                  ## z = 100 (first break wins), k = 1 -> 0 + 0
}
