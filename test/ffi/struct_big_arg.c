/* Pure-arithmetic C stub for the FFI harness (no libc). SysV: a struct LARGER than 16 bytes
   (Big = 24 bytes, three eightbytes) is class MEMORY — passed BY VALUE ON THE STACK (not in
   registers, not by hidden pointer). The callee reads b.a at 0(%rsp-arg), b.b at 8, b.c at 16.
   sumbig is ORDER/VALUE-sensitive (a + b - c), so a mis-copied stack slot yields a wrong exit. */
struct Big { long a; long b; long c; };
long sumbig(struct Big b) { return b.a + b.b - b.c; }
