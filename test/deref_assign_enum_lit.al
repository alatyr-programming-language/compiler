## §4: storing an ENUM LITERAL with scalar payloads through a pointer — `deref(p) = E.B(30, 12)`. Was a
## silent bug: an enum-literal source fell to the scalar DerefAssign path and stored ONE garbage word
## (dropping the disc/payload). Now the discriminant is stored at word 0 and each scalar payload at
## words 1.. (down-growing pointee, matching the enum match read). Round-trip: store E.B(30,12) into a
## mmap'd region (base+64, headroom below), read via a `ptr(mut E)` param match → 30 + 12 = 42.
## (A struct/str/nested-enum payload is deferred; the base-pointer case awaits the up-growing flip.)
## x86_64-only: the mmap syscall number is x86-specific.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
E := enum { A(u64), B(u64, u64) }
reade := fn(p : ptr(mut E)) -> u64 { match deref(p) { E::A(x) => { x } E::B(x, y) => { x + y } } }
main := fn() -> u64 {
  r0 := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, 0 - 1), 0)
  base := unchecked bitcast(usize, r0)
  p := unchecked bitcast(ptr(mut E), base + 64)
  deref(p) = E.B(30, 12)
  reade(p)
}
