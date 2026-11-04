## #1434 — the same misroute at `shr`: the emit arm matched the callee TEXT and read argument 1 of a
## one-argument call, so a declared `shr` crashed the compiler. NON-VACUOUS on the parent 48ecfed4
## (native x86_64, tree Stage1): `alatyr build` exits **139** (SIGSEGV, no diagnostic); the identical
## program with the callee spelled `shrx` answers 42 there. `shr` is not a keyword (Grammar §2.3) and the
## program's declaration wins (Declarations §6.1), so this is 10 + 32 — and it is the program's own `shr`,
## not a shift: the identity returns 10, so a shift would have answered 5.
shr := fn(x : u64) -> u64 { x }
main := fn() -> u64 {
  shr(10) + 32
}
## expect: run 42
