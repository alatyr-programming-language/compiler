/* FFI receiving-side stub (no libc). C calls BACK into the exported Alatyr @abi(c) fn `alt_subd`
   (SysV: a=%xmm0, b=%xmm1 -> %xmm0). drivef computes 50.5 - 8.5 = 42.0, truncated to 42. */
extern double alt_subd(double a, double b);
long drivef(void) { double r = alt_subd(50.5, 8.5); return (long) r; }
