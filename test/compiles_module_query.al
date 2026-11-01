## Module-level capability queries use order-independent module scope.
takes_str := fn(s : str) -> u64 { 42 }
good := compiles(1)
bad := compiles(takes_str(1))

main := fn() -> u64 {
  if good and not bad { return 42 }
  return 1
}
## expect: run 42
