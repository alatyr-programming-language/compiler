## Companion to `checked_add_ovf`: an `unchecked` scope DROPS the compiler-emitted `+` overflow guard
## (VERIFY_CHK / A64_CHK / RV_CHK / WAT_CHK false), so `u64 MAX + 1` wraps to 0 (two's-complement) and
## the program exits 0 — proving the guard is scoped, not unconditional. aarch64-only via run_a64.
main := fn() -> u64 {
  a : u64 = 18446744073709551615
  b := unchecked { a + 1 }
  return b
}
