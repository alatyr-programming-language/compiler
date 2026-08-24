## Checked-mode SLICE bounds trap (I11 / CG-7): indexing a typed array-slice out of range traps
## deterministically via `ud2` (→ SIGILL). `arr[0..3]` is a length-3 view; a RUNTIME index `i = 5` is
## out of range, so `s[i]` compares against the slice's runtime len word and traps. x86_64-only (like
## the frame/global-array bounds), registered `run_x86`. Exit 132 (128 + SIGILL 4).
main := fn() -> u64 {
  arr := [10, 20, 30]
  s := arr[0..3]
  i := 5
  return s[i]
}
