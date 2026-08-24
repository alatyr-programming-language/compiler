## I11 / CG-7 + CG-13 scoping: inside an `unchecked` scope the div-by-zero guard is ABSENT and the
## operation takes its hardware-defined behaviour — which is arch-specific, so this fixture is
## registered PER BACKEND and classifies the raw result INSIDE the program (an exit code truncates
## mod 256, and the riscv64 value is all-ones = 255):
##   x86_64  — `divq` faults (`#DE` → SIGFPE), the program never returns   → exit 136
##   aarch64 — `udiv` by zero is defined as 0                              → exit 41
##   riscv64 — `divu` by zero is defined as all-ones                       → exit 42
## The checked dual is `checked_udiv_zero` (exit 132 on every backend). Not registered for wasm:
## `i64.div_u` traps unconditionally there, so `unchecked` cannot reach a defined value.
divide := fn(a : u64, b : u64) -> u64 { return unchecked (a / b) }
main := fn() -> u64 {
  q := divide(42, 0)
  if q == 0 { return 41 }
  ones : u64 = 18446744073709551615
  if q == ones { return 42 }
  return 7
}
