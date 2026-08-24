## Checked bounds for a BY-REFERENCE fixed-array PARAM `a : [T; N]` (I11) — the callee knows the static
## length N from its own type (the parser now records N in the param's `pps` slot; bind_param puts it in
## the slot's `sns`), so `a[i]` traps on an out-of-range index (SIGILL, exit 132) with NO passed length.
## Was previously unchecked → an OOB index crashed (SIGSEGV/141) instead of a clean trap. `unchecked` drops it.
sum := fn(a : [u64; 3], i : u64) -> u64 { return a[i] }
main := fn() -> u64 {
  arr := [10, 20, 30]
  return sum(arr, 8)
}
