## A generic body with only a direct parameter expression satisfies both limits.
@limits(no_unchecked, no_abstractions)
identity := fn(T : type, x : T) -> T {
  x
}
main := fn() -> u64 {
  movq(rax, 60)
  movq(rdi, 42)
  syscall()
  return 0
}
