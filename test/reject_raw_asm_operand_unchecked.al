## #659: an `unchecked` wrapper around a literal is an `Expr::Unchecked`, not an `Expr::Num`, so it is
## not one of the two operand forms spec ch.80 §2/§6 admits. Measured on the parent: `check` rc 0,
## `build` rc 0, exit 40 where 42 was due.
main := fn() -> u64 {
  movq(rdi, 40)
  movq(rbx, unchecked 2)
  addq(rdi, rbx)
  movq(rax, 60)
  syscall()
  return 0
}
