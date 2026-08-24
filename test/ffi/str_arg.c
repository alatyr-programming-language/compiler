/* Pure-arithmetic C stub (no libc). An Alatyr str is a {ptr, len} pair passed by value in two
   INTEGER registers (ptr=%rdi, len=%rsi). strlen42 reads len (word 1) + the first byte (through the
   ptr in word 0), so a swapped eightbyte yields a wrong exit. 10 + 0x20 = 42. */
struct S { unsigned char* p; long n; };
long strlen42(struct S s) { return s.n + (long)s.p[0]; }
