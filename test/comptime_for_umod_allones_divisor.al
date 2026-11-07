## e2e (#1493) — a `u64` range bound's `%` and `/` by a divisor whose bit pattern reads as a negative
## `i64` divide UNSIGNED (Types §3.2, Concurrency §6.5). The `MIN % -1` -> 0 rule of Concurrency §6.1
## is about a signed minimum and a signed -1; a `u64` divisor `2^64 - 1` is not -1, so `5 % D` is 5.
##
## Expected: 42 on all four backends. It exits 1..3 by the term that is wrong:
##   1   `5 % D`       = 5 % (2^64 - 1) = 5   (a signed reading takes the `% -1` shortcut: 0)
##   2   `7 % (D - 1)` = 7 % (2^64 - 2) = 7   (a signed reading: 7 % -2 = 1)
##   3   `D / (D - 1)` = 1                    (a signed reading: -1 / -2 = 0)
## Measured on the parent (main `7621cdfe`, Stage1 built by the seed, native x86_64): exit 1 on all
## four backends; each term alone ran 0, 1 and 0 iterations.
D : u64 = 18446744073709551615

main := fn() -> u64 {
  mut a : u64 = 0
  comptime for i in 0 .. 5 % D { a = a + 1 }
  if a != 5 { return 1 }
  mut b : u64 = 0
  comptime for i in 0 .. 7 % (D - 1) { b = b + 1 }
  if b != 7 { return 2 }
  mut c : u64 = 0
  comptime for i in 0 .. D / (D - 1) { c = c + 1 }
  if c != 1 { return 3 }
  return 42
}
## expect: run 42
