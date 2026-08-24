/* FFI receiving-side stub (no libc). C calls the exported Alatyr @abi(c) fn `alt_mkbig`, which
   RETURNS a 24-byte struct via SRET (hidden %rdi result pointer; x->%rsi, y->%rdx, z->%rcx). The
   callee writes {x, y, z} through the pointer and returns it in %rax. 50 - 20 + 12 = 42. */
struct Big { long a; long b; long c; };
extern struct Big alt_mkbig(long x, long y, long z);
long drivemkbig(void) { struct Big r = alt_mkbig(50, 20, 12); return r.a - r.b + r.c; }
