/* FFI receiving-side stub (no libc). C receives an all-float 16-byte struct BY VALUE (%xmm0:%xmm1)
   returned from the exported Alatyr @abi(c) fn `alt_mkd`, which SWAPS its args (a=y, b=x). drivemkd:
   alt_mkd(6.0, 12.0) -> {a=12.0, b=6.0}; d.a*3 + d.b = 36 + 6 = 42. A missing SSE-return remap
   leaves %xmm0/%xmm1 as the pass-through incoming args {6.0, 12.0} -> 18 + 12 = 30 (wrong). */
struct D { double a; double b; };
extern struct D alt_mkd(double x, double y);
long drivemkd(void) { struct D d = alt_mkd(6.0, 12.0); return (long)(d.a * 3.0 + d.b); }
