## #1237: storing a multi-word STRUCT returned by a CALL through a pointer — `deref(p) = mk(40)`.
## Was a silent wrong value: the source is neither a struct literal nor a struct VAR, so it fell to the
## scalar DerefAssign path (`deref_store_words` answers 1 for a non-Var) and stored ONE word — only
## `.a`. `q.b` read the never-written pointee word, so `q.a + q.b` answered 40 for 42. Now every word
## the call leaves in `emit_retreg(k)` is staged and copied whole to the pointee (Memory §4.3/§4.6,
## Codegen §4, spec v1.8.0). x86_64-only: the mmap syscall number is x86-specific.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
P := struct { a : u64, b : u64, c : u64 }
mk := fn(x : u64) -> P { P(a = x, b = 2, c = 3) }
main := fn() -> u64 {
  r := unchecked sys_mmap(std::sysno::MMAP, 0, 65536, 3, 34, bitcast(usize, 0 - 1), 0)
  p : ptr(mut P) = unchecked bitcast(ptr(mut P), bitcast(usize, r))
  deref(p) = mk(40)
  q := deref(p)
  q.a + q.b
}
## expect(x86_64): run 42
