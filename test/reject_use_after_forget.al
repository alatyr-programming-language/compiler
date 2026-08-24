## Use-after-forget (spec §10): forget(x) DISCHARGES the linear handle x, so a later mention
## of x (here in the `y := x` binding) is a use-after-consume error — check must reject (rc 1).
main := fn() -> u64 {
  x := 5
  forget(x)
  y := x
  y
}
