## §4: storing a STRUCT LITERAL through a pointer — `deref(p) = Pt(x, y)`. Was a silent bug: a literal
## source fell to the scalar DerefAssign path (deref_store_words returns 1 for a non-Var) and stored ONE
## garbage word. Now each field is evaluated and stored to the pointee (down-growing, matching the field
## read). Verified round-trip: store {30, 12} into a mmap'd region (base+64, headroom below the pointer
## so the down-growing store stays in-region), read back via a `ptr(mut Pt)` param → 30 + 12 = 42.
## (The full up-growing layout unification — so a pointer AT a region base also works — is the separate
## §4 core refactor.) x86_64-only: the mmap syscall number is x86-specific.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
Pt := struct { x : u64, y : u64 }
readpt := fn(p : ptr(mut Pt)) -> u64 { deref(p).x + deref(p).y }
main := fn() -> u64 {
  r0 := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, 0 - 1), 0)
  base := unchecked bitcast(usize, r0)
  p := unchecked bitcast(ptr(mut Pt), base + 64)
  deref(p) = Pt(x = 30, y = 12)
  readpt(p)
}
