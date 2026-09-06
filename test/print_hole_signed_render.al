## e2e (four-backend TEXT agreement) — a `{}` template hole whose static type is a SIGNED integer
## must render base-10 with a leading `-` for a negative two's-complement value: Functions §7.1 routes
## every hole through the scalar rendering layer, and Stdlib appendix §2 fixes that layer's integer
## form as "an integer in base-10 (a leading `-` for a negative two's-complement value, minimal
## digits, `0` for zero)". The spec attaches no exemption for a non-x86 or freestanding target.
##
## Issue #443: aarch64, riscv64 and WAT each routed EVERY hole through one unsigned-only renderer, so
## this program compiled clean, exited 42, and wrote 2^64-n instead of -n on three of four backends.
## The exit code was CORRECT, which is why the sweeps (an exit-code cross-check) could not see it.
##
## Refs #444: this is the first cross-backend row in the suite that compares a NEGATIVE rendering at
## all. The assertion is therefore the exact stdout on all four backends (run_x86_out +
## run_a64_out + run_rv64_out + run_wat_out against the SAME golden bytes), never the exit code, and
## never a length or digest of a fragment. The non-vacuity test for the STAGE itself — planting a
## renderer that drops the sign and requiring the stage to report it — is #444's residual, not this
## fixture's.
##
## Boundaries covered, per signed width: the minimum (no positive counterpart — a naive `0 - v`
## negation of it overflows and is the obvious wrong fix), -1, -2, a mid negative, zero, a positive
## control, the i64 maximum (a large positive that a signed renderer must not corrupt), and a
## `u64` hole at 2^64-1 (an UNSIGNED hole, whose bytes must not move).
main := fn() -> u64 {
  mn : i64 = -9223372036854775808
  m1 : i64 = 0 - 1
  m2 : i64 = 0 - 2
  mid : i64 = 0 - 128
  z : i64 = 0
  pos : i64 = 7
  mx : i64 = 9223372036854775807
  s8 : i8 = 0 - 128
  s16 : i16 = 0 - 32768
  s32 : i32 = 0 - 2147483648
  sz : isize = 0 - 3
  u : u64 = 18446744073709551615
  print("i64min {}\n", mn)
  print("m1 {}\n", m1)
  print("m2 {}\n", m2)
  print("mid {}\n", mid)
  print("zero {}\n", z)
  print("pos {}\n", pos)
  print("i64max {}\n", mx)
  print("i8min {}\n", s8)
  print("i16min {}\n", s16)
  print("i32min {}\n", s32)
  print("isize {}\n", sz)
  print("u64max {}\n", u)
  42
}
