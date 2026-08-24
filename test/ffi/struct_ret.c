/* Pure-arithmetic C stubs for the FFI harness (no libc). SysV returns a struct <= 16 bytes in the
   classed result registers: an all-integer Pt{long a; long b} in %rax:%rdx, an all-double
   D{double x; double y} in %xmm0:%xmm1. The Alatyr side reads each returned field separately and
   subtracts, so a swapped eightbyte (wrong result register) changes the exit code. */
struct Pt { long a; long b; };
struct D  { double x; double y; };
struct Pt mkpt(long a, long b)     { struct Pt p; p.a = a; p.b = b; return p; }
struct D  mkd(double x, double y)  { struct D d;  d.x = x; d.y = y; return d; }
