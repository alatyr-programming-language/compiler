## Issue #794 — the x86_64 ABI (`sysv`, ABI appendix §4.1) makes a callee preserve rbx, r12..r15. The
## register allocator relies on that: `main` below keeps `a`, `b` and `c` in %rbx, %r12 and %r13 across
## the call to `work`. `work` and `setp` are lowered by the text emitter, which used those three as
## scratch (an arithmetic operand, a `match` scrutinee, a pointee pointer for a multi-word field store)
## without saving them. On the parent this built with rc 0 and ran to 8 where 42 was due: `main` read
## the callees' scratch values as its own locals. Every text-lowered function now saves the whole
## callee-saved set after its prologue and restores it before its epilogue.
W := struct { x : u64, y : u64 }
P := struct { a : u64, s : W }
setp := fn(p : ptr(mut P), n : u64) -> u64 {
  deref(p).s = W(x = n, y = n + 1)
  0
}
work := fn(n : u64) -> u64 {
  mut q := P(a = 1, s = W(x = 0, y = 0))
  z := setp(ptr(mut q), n)
  mut k : u64 = 0
  match n {
    1 => { k = 7 }
    2 => { k = 9 }
    _ => { k = 11 }
  }
  k + q.s.y - n + z
}
main := fn() -> u64 {
  a : u64 = 10
  b : u64 = 20
  c : u64 = 30
  x := work(2)
  a + b + c + x - 28
}
