## FN-6 CAPTURE + a `comptime if` body — the comptime-if is folded (handled like a runtime `if`), and a
## captured scalar `c` referenced in the kept branch resolves against its injected param. The prelude
## namespace identifiers in the condition (`target`, `Arch`) are NOT mistaken for captures. Whichever
## branch the target keeps, it is `40 + c` → 42. (A capturing comptime-FOR/comptime-MATCH body is
## rejected fail-loud instead — captures can't be injected into an unrolled comptime body.)
##
## BOTH branches reference the capture, and both answer 42, on purpose. The else branch used to be
## `r = n`, which answers 40 — target-CONDITIONAL, while the corpus row that the a64/rv64/wasm sweeps
## read carries ONE want (the x86_64 exit). No sweep saw the difference only because every non-x86
## backend trapped on `mut r := n` before it could run: #430 removed that trap on wasm and the very
## next run of the wasm sweep would have called the target-correct 40 a silent miscompile. Making both
## branches assert the capture keeps the point of the fixture and adds the branch nobody was checking.
main := fn() -> u64 {
  c := 2
  f := fn(n : u64) -> u64 {
    mut r := n
    comptime if target.arch == Arch.x86_64 { r = r + c } else { r = n + c }
    return r
  }
  return f(40)
}
