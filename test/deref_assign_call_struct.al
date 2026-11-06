## §4 / Memory §4 + Types §4.3 — storing a MULTI-WORD STRUCT returned BY A CALL through a pointer:
## `deref(p) = mk(40)` writes the WHOLE pointee. Was a SILENT WRONG VALUE (I11): the call fell to the
## scalar DerefAssign store, which moved word 0 alone, so `q.b` read the untouched mmap byte — MEASURED
## **40** where `q.a + q.b` owes 42, on the seed and on the tree alike. The spellings beside it already
## worked and are unchanged: `deref(p) = Pt(…)` (`deref_assign_struct_lit.al`), a struct VAR, and
## `deref(vd) = deref(vs)`. x86_64-only: the mmap syscall number is x86-specific.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
P := struct { a : u64, b : u64, c : u64 }
mk := fn(x : u64) -> P { P(a = x, b = 2, c = 3) }
main := fn() -> u64 {
  r := unchecked sys_mmap(std::sysno::MMAP, 0, 65536, 3, 34, bitcast(usize, 0 - 1), 0)
  p : ptr(mut P) = unchecked bitcast(ptr(mut P), bitcast(usize, r))
  deref(p) = mk(40)
  q := deref(p)
  if q.a != 40 { return 1 }
  if q.c != 3 { return 2 }                 ## the LAST word moved too, not only the first two
  q.a + q.b                                ## 40 + 2 = 42 (was 40: word 1 never landed)
}
## expect(x86_64): run 42
