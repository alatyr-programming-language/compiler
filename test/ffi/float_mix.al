## FFI: MIXED integer + float scalar args (independent SysV counters). mixargs lives in
## test/ffi/float_mix.c; SysV routes the two i64 args to %rdi/%rsi and the two f64 args to
## %xmm0/%xmm1 (int and SSE arg registers are counted SEPARATELY). mixargs weights each arg
## distinctly (i*8 + j*4 + x*2 + y), so any wrong register mapping (an int in an xmm reg, a
## shared counter, or a swap) yields a different exit code.
mixargs := @extern @abi(c) fn(i : i64, x : f64, j : i64, y : f64) -> i64

main := fn() -> u64 {
  return u64(mixargs(1, 2.0, 3, 18.0))   ## 1*8 + 3*4 + 2*2 + 18 = 8 + 12 + 4 + 18 = 42
}
