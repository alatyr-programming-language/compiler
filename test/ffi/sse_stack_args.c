/* Pure-arithmetic C stub (no libc). SysV: a..h in %xmm0..%xmm7, i ON THE STACK (0(%rsp)). addf9
   sums all nine, returning the double in %xmm0, so a mis-placed 9th slot yields a wrong exit. */
double addf9(double a, double b, double c, double d, double e, double f, double g, double h, double i) {
  return a + b + c + d + e + f + g + h + i;
}
