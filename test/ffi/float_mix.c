/* Pure-arithmetic C stub for the FFI harness (no libc). SysV counts integer and SSE argument
   registers INDEPENDENTLY: i -> %rdi, j -> %rsi (int0, int1); x -> %xmm0, y -> %xmm1 (sse0, sse1).
   Distinct weights make any wrong reg mapping / shared counter / swap change the exit code. */
long mixargs(long i, double x, long j, double y) {
  return i * 8 + j * 4 + (long)(x * 2) + (long)y;
}
