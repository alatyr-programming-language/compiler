## Helper module for the multi-file located-diagnostic test (reject_located_multi). Valid on its
## own; its several lines precede the entry module in the concatenated check buffer, so a naive
## whole-buffer line count would misreport the entry module's error line.
helper := fn(x : u64) -> u64 {
  y := x + 1
  z := y + 1
  return z
}
