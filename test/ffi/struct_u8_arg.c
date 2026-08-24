/* Pure-arithmetic C stub. SysV packs struct Pair into one INTEGER eightbyte. */
struct Pair { unsigned char a; unsigned char b; };
long sumbytes(struct Pair p) { return (long)p.a + 263L * (long)p.b; }
