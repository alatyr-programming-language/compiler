## §4 / Memory §4 — storing an ENUM returned BY A CALL through a pointer: `deref(p) = mk(40)` writes
## disc AND every payload word. Was a SILENT WRONG VALUE (I11): the call fell to the scalar store, so
## the earlier `deref(p) = E.B(9)` survived and the match answered **9** where `E.A(40, 2)` owes 42.
## The enum-literal spelling beside it already worked (`deref_assign_enum_lit.al`); a CALL source did
## not. x86_64-only: the mmap syscall number is x86-specific.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
E := enum { A(u64, u64), B(u64) }
mk := fn(x : u64) -> E { E.A(x, 2) }
main := fn() -> u64 {
  r := unchecked sys_mmap(std::sysno::MMAP, 0, 65536, 3, 34, bitcast(usize, 0 - 1), 0)
  p : ptr(mut E) = unchecked bitcast(ptr(mut E), bitcast(usize, r))
  deref(p) = E.B(9)
  deref(p) = mk(40)
  match deref(p) {
    E::A(a, b) => { a + b }              ## 40 + 2 = 42 (was 9: the call store never landed)
    E::B(z) => { z }
  }
}
## expect(x86_64): run 42
