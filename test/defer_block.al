## DEFER (§9.3): the `defer { … }` BLOCK form — S1 then S2 run TOGETHER as ONE LIFO unit (in order).
## The block's statements are ordinary statements: `f` runs them on exit via the drain (calling mark(1)
## then mark(2) → ACC base-10 = 12), and `main` observes ACC AFTER `f` returned (defer semantics: the
## return VALUE is eval'ed before the drain; read the global after). If the block ran as two SEPARATE
## defers or in REVERSE order, ACC would be 21; if dropped, 0.
mut ACC : u64 = 0
mark := fn(n : u64) -> u64 { ACC = ACC * 10 + n ; 0 }
f := fn() -> u64 {
  defer { mark(1); mark(2) }
  return ACC
}
main := fn() -> u64 { _ := f() ; return ACC }