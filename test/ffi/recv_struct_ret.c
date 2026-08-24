/* FFI receiving-side stub (no libc). C receives a 16-byte all-integer struct BY VALUE (%rax:%rdx)
   returned from the exported Alatyr @abi(c) fn `alt_mkpt`. drivemk: alt_mkpt(30,12) -> {30,12} -> 42. */
struct Pt { long x; long y; };
extern struct Pt alt_mkpt(long a, long b);
long drivemk(void) { struct Pt p = alt_mkpt(30, 12); return p.x + p.y; }
