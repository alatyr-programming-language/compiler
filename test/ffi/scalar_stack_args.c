/* Pure-arithmetic C stub (no libc). SysV: a..f in %rdi..%r9, g and h ON THE STACK (g at the lowest
   address). add8 sums all eight, so a mis-placed / mis-ordered stack slot yields a wrong exit. */
long add8(long a, long b, long c, long d, long e, long f, long g, long h) {
  return a + b + c + d + e + f + g + h;
}
