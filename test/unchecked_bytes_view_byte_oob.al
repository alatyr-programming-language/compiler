## The `unchecked` side of `test/checked_bytes_view_byte_oob.al` (CT-11 / CG-7): inside an
## `unchecked` scope the bounds check on `bytes(s)[i]` is OMITTED, so the same out-of-range read
## must NOT trap. Only the check is dropped — the ADDRESS is unchanged, which the in-range row
## pins first (issue #410 made `unchecked s[i]` parse as `(unchecked s)[i]` and read frame slot 0).
##
## Row 1 — in range under `unchecked`: `bytes(s)[1]` must still be the string's own byte, 'b' = 98.
##   A slot-0 / wrong-base read cannot produce it; the neighbours 'A' = 65 and 'C' = 67 are non-zero
##   and pairwise distinct, so a one-off address error is visible.
## Row 2 — out of range under `unchecked`: the read must complete. Its value is unspecified (a byte
##   of the `.rodata` that follows the literal's run), so the assertion is the one property that IS
##   specified: `movzbq` zero-extends, therefore the result is a BYTE. A compiler that kept the
##   check here would die of SIGILL (132) instead of reaching either return.
## Each failure owns its own code from 100 (#386); the success value is 42. Registered `run_x86`:
## the str byte index is an x86_64-only surface today (a64/rv64/wasm fail loud on every str index),
## so this row is deliberately outside the cross-target sweeps.
main := fn() -> u64 {
  s := "AbCdEf"
  if u64(unchecked bytes(s)[1]) != 98 { return 111 }
  i := 9
  past := u64(unchecked bytes(s)[i])
  if past > 255 { return 112 }
  return 42
}
