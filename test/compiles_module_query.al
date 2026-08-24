## Module-level capability queries use order-independent module scope.
takes_str := fn(s : str) -> u64 { 42 }
good := compiles(1)
bad := compiles(takes_str(1))
