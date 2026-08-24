## FN-6 CAPTURE + a `comptime if` body — the comptime-if is folded (handled like a runtime `if`), and a
## captured scalar `c` referenced in the kept branch resolves against its injected param. The prelude
## namespace identifiers in the condition (`target`, `Arch`) are NOT mistaken for captures. On x86_64 the
## kept branch is `r = r + c` → 40 + 2 = 42. (A capturing comptime-FOR/comptime-MATCH body is rejected
## fail-loud instead — captures can't be injected into an unrolled comptime body.)
main := fn() -> u64 {
  c := 2
  f := fn(n : u64) -> u64 {
    mut r := n
    comptime if target.arch == Arch.x86_64 { r = r + c } else { r = n }
    return r
  }
  return f(40)
}
