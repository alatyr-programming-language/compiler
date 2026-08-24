/* Pure-arithmetic C stub for the FFI harness (no libc). SysV: two double args in %xmm0,%xmm1;
   the double result returns in %xmm0. subd is ORDER-SENSITIVE (a - b), so a swapped xmm0/xmm1
   yields a different exit code. */
double subd(double a, double b) { return a - b; }
