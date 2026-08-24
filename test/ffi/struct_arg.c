/* Pure-arithmetic C stubs for the FFI harness (no libc). SysV: a 16-byte all-integer struct is
   passed BY VALUE in two integer regs (p.x=rdi, p.y=rsi); a 1-eightbyte struct in one (rdi).
   sumpt is ORDER-SENSITIVE (p.x - p.y), so a swapped rdi/rsi yields a different exit code. */
struct Pt  { long x; long y; };
struct One { long v; };
long sumpt(struct Pt p)  { return p.x - p.y; }
long useone(struct One o) { return o.v; }
