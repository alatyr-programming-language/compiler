/* FFI receiving-side stub (no libc). C calls BACK into the exported Alatyr @abi(c) fn `alt_add`
   (SysV: a=%rdi, b=%rsi -> %rax). Round-trips Alatyr -> C -> Alatyr; drive returns 20 + 22 = 42. */
extern long alt_add(long a, long b);
long drive(void) { return alt_add(20, 22); }
