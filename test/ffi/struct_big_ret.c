/* Pure-arithmetic C stub for the FFI harness (no libc). SysV: a struct LARGER than 16 bytes
   (Big = 24 bytes) is class MEMORY on RETURN too — delivered via SRET (a hidden result pointer):
   the caller passes the destination's address in %rdi (shifting the real args a->%rsi, b->%rdx,
   c->%rcx), the callee writes {a, b, c} through it and returns the pointer in %rax. The Alatyr side
   reads all three returned fields and combines them (a - b + c), so a mis-placed field changes the exit. */
struct Big { long a; long b; long c; };
struct Big mkbig(long a, long b, long c) { struct Big r; r.a = a; r.b = b; r.c = c; return r; }
