## e2e (build_reject): a whole-STRUCT store through a pointer from an if/match BRANCH —
## `deref(p) = if cond { Rec(…) } else { Rec(…) }` into a MULTI-WORD pointee. A branch value is
## neither a struct-literal, a var, nor a pointee-deref (the source forms the multi-word store paths
## handle), so it fell to the scalar store path and moved only word 0 (a silent word-drop). Lower now
## FAILS LOUD; the working spelling binds the branch to a local first (`t := if …; deref(p) = t`).
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
Rec := struct { a : u64, b : u64 }
main := fn() -> u64 {
  r0 := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, 0 - 1), 0)
  base := unchecked bitcast(usize, r0)
  p := unchecked bitcast(ptr(mut Rec), base + 128)
  cond := true
  deref(p) = if cond { Rec(a = 30, b = 12) } else { Rec(a = 0, b = 0) }
  u64(deref(p).a + deref(p).b)
}
