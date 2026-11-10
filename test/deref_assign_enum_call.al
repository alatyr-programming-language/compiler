## #1237: storing a multi-word ENUM returned by a CALL through a pointer — `deref(p) = mk(40)` where
## `mk : fn(u64) -> E` and `E := enum { A(u64, u64), B(u64) }`. Was a silent wrong value: an aggregate
## CALL source fell to the scalar DerefAssign path and stored ONE word — the discriminant — so the
## payload words still held the PREVIOUS `deref(p) = E.B(9)` store and the `A(a, b)` arm answered
## 9 + 0 = 9 for 40 + 2. Now disc and both payloads land (Memory §4.3/§4.6, Codegen §4, v1.8.0).
## x86_64-only: the mmap syscall number is x86-specific.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
E := enum { A(u64, u64), B(u64) }
mk := fn(x : u64) -> E { E.A(x, 2) }
main := fn() -> u64 {
  r := unchecked sys_mmap(std::sysno::MMAP, 0, 65536, 3, 34, bitcast(usize, 0 - 1), 0)
  p : ptr(mut E) = unchecked bitcast(ptr(mut E), bitcast(usize, r))
  deref(p) = E.B(9)
  deref(p) = mk(40)
  match deref(p) {
    E::A(a, b) => { a + b }
    E::B(z) => { z }
  }
}
## expect(x86_64): run 42
