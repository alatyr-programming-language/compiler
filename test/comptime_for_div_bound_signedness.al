## e2e (#1233) — controls for the `MIN / -1` diagnostic: a range bound's `/` and `%` divide in the
## operation's own signedness (Types §3.2: signedness lives in the operation), and a signed `/ -1`
## that is not `MIN / -1` still folds.
##
## Expected: 42 on all four backends. `unchecked ((0 - 9) / (0 - 1))` is 9. Over `u64`, `D / Q` is
## (2^64 - 1) / 2^62 = 3 and `D % 10` is 5; `H / D` is 2^63 / (2^64 - 1) = 0 (the pattern pair a signed
## division would read as `MIN / -1`).
## Measured on the parent (#1234's head `be44a601`, stacked on #1229; native x86_64): the compiler
## itself died with SIGFPE (rc 136) on all four targets: its signed `idiv` over the patterns of `H / D`
## is `MIN / -1`.
D : u64 = 18446744073709551615
Q : u64 = 4611686018427387904
H : u64 = 9223372036854775808

main := fn() -> u64 {
  mut a : u64 = 0
  comptime for i in 0 .. unchecked ((0 - 9) / (0 - 1)) { a = a + 1 }
  if a != 9 { return 1 }
  mut b : u64 = 0
  comptime for i in 0 .. D / Q { b = b + 1 }
  if b != 3 { return 2 }
  mut c : u64 = 0
  comptime for i in 0 .. D % 10 { c = c + 1 }
  if c != 5 { return 3 }
  mut d : u64 = 0
  comptime for i in 0 .. H / D { d = d + 1 }
  if d != 0 { return 4 }
  return 42
}
