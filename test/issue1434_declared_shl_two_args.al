## #1434 — the SILENT WRONG VALUE of the same family, and the more serious half. The IR builder mapped the
## callee TEXT `shl` to a shift and emitted it without asking whether the program declared that name — the
## guard `not ib_fn_named(bp, cs, cl)` its two neighbouring arms (brand constructor, layout query) already
## ask. NON-VACUOUS on the parent 48ecfed4 (native x86_64, tree Stage1): `alatyr build` **succeeds** and
## the program answers **72** where 42 is due — `shlq %cl, %rsi` sits in the emitted assembly and there is
## no `call …__shl` — so nothing was refused, the value is simply wrong. The identical program with the
## callee spelled `shlx` answers 42 there. A declared name is a call to that declaration (Grammar §2.3:
## `shl` is not a keyword; Declarations §6.1: the inner declaration wins), so this is 10 + 32.
shl := fn(a : u64, b : u64) -> u64 { a }
main := fn() -> u64 {
  shl(10, 2) + 32
}
## expect: run 42
