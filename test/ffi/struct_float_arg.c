/* Pure-arithmetic C stubs for the FFI harness (no libc). SysV: an all-double struct D{x,y} is
   classed into two SSE eightbytes (d.x=%xmm0, d.y=%xmm1); a mixed M{long i; double d} into one
   INTEGER (m.i=%rdi) + one SSE (m.d=%xmm0) eightbyte, counted on INDEPENDENT counters. dsum is
   order-sensitive (x - y); usemix checks the int field rides a GPR and the float field an xmm. */
struct D { double x; double y; };
struct M { long i; double d; };
double dsum(struct D d)   { return d.x - d.y; }        /* 30 - 5  = 25 */
long   usemix(struct M m) { return m.i - (long)m.d; }  /* 20 - 3  = 17 */
