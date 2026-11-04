## #1434 — `emit_gas` matched the callee TEXT `shl` before the generic call and read argument 1 of a
## one-argument call: `arg_expr_at` answers null there (its own `res := 0`) and `emit_gas` dereferences
## its argument unguarded. NON-VACUOUS on the parent 48ecfed4 (native x86_64, tree Stage1): `alatyr
## build` exits **139** (SIGSEGV, no diagnostic); the identical program with the callee spelled `shlx`
## answers 42 there, and the same callee called with two arguments answers 0. A declared name is a call to
## that declaration (Grammar §2.3: `shl` is not a keyword, built-ins are prelude identifiers; Declarations
## §6.1: the inner declaration wins), so this is 10 + 32.
shl := fn(x : u64) -> u64 { x }
main := fn() -> u64 {
  shl(10) + 32
}
## expect: run 42
