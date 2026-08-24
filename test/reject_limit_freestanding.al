## sema/§ limits (I5/I9, FND-10): a `@limits(freestanding)` translation unit must not depend on the OS —
## a direct call to a `@abi(syscall)` fn (a raw syscall, the clearest OS dependence) violates the
## contract → REJECT.
@limits(freestanding)
mysys := @abi(syscall) fn(num : usize, code : usize) -> isize
f := fn() -> u64 { r := mysys(60, 0)
  return 0 }
main := fn() -> u64 { return f() }
