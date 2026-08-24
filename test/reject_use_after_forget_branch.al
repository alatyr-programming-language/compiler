## Use-after-discharge across a nested BRANCH (spec §10): forget(x) discharges x unconditionally,
## then a later `if` branch uses x — a use-after-consume error caught by the block-recursing scan (rc 1).
main := fn() -> u64 {
  x := 5
  forget(x)
  mut r := 0
  if x > 0 { r = x }
  r
}
