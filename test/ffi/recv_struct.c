/* FFI receiving-side stub (no libc). C passes a 16-byte all-integer struct BY VALUE (p.x=%rdi,
   p.y=%rsi) into the exported Alatyr @abi(c) fn `alt_sumpt`. drivep: alt_sumpt({50,15}) + 7 = 42. */
struct Pt { long x; long y; };
extern long alt_sumpt(struct Pt p);
long drivep(void) { struct Pt p = {50, 15}; return alt_sumpt(p) + 7; }
