/* FFI receiving-side stub (no libc). C passes a 24-byte struct BY VALUE ON THE STACK into the
   exported Alatyr @abi(c) fn `alt_sumbig`. drivebig: alt_sumbig({50, 17, 25}) = 50 + 17 - 25 = 42. */
struct Big { long a; long b; long c; };
extern long alt_sumbig(struct Big b);
long drivebig(void) { struct Big b = {50, 17, 25}; return alt_sumbig(b); }
