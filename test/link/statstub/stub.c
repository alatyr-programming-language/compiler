/* Pure-arithmetic C stub for the MOD-9 static-link harness (no libc). SysV: a in %rdi. The harness
   compiles this to an object (cc -c) and archives it (ar rcs libstub.a stub.o) so `ld -static … -lstub`
   absorbs it. add1(41) = 42. */
long add1(long a) { return a + 1; }
