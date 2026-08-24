## FN-6 §6.2 regression, aarch64 + riscv64 float pool — TWO DISTINCT float literals in the body of a
## higher-order fn that the driver's D-cap path DEEP-CLONES for a capturing closure.
##
## A float literal's rodata label IS its source-span start; a `FloatLit` carries no separate label
## field, so unlike a string literal (whose label index the clone renumbers) the clone copies the span
## VERBATIM. The original `scale` and its `__hoflam<fnpos>` clone are therefore two decls carrying the
## same two offsets, and the rodata walk runs per decl — so each `.Lflt<offset>` cell was written twice
## while every load resolved to the one name, and the assembler refused the file. x86_64 already shares
## one cell per offset; a64/rv64 now do the same.
##
## PRE-FIX MEASUREMENT (this tree's parent commit): `alatyr aarch64` emitted 2 definitions for each of
## the 2 labels, and aarch64-unknown-linux-gnu-as reported both `.Lflt<offset>` lines as a symbol that
## was already defined; riscv64-unknown-linux-gnu-as reported the same two labels the same way. Only
## the DEFINITIONS doubled — the 4 loads already resolved to one name each. (The diagnostic is
## PARAPHRASED and its offsets elided on purpose: a header that quotes its own needle verbatim makes a
## grep-based check pass on an unfixed tree, which has happened twice here.)
##
## TWO literals, not one, and both are load-bearing: a dedup keyed too coarsely (per HOF clone rather
## than per source offset) would collapse them into one cell and the value would come out wrong rather
## than merely failing to assemble.
## MEASURED, all four backends: x86_64 = 42 (c := 10; g(10) = 20; 20 + 20 = 40; + u64(3.5) = 43;
## - u64(1.25) = 42), and a clean TRAP on the other three — wasm 134, aarch64 and riscv64 133 (SIGTRAP)
## — because none of them models the indirect call through the callable param, which is a SEPARATE gap
## from the pool defect. So on a64/rv64 what this fixture pins is the phase, not the value: the file
## now ASSEMBLES and LINKS and the program reaches its own trap, instead of `as` refusing the file
## outright. Only x86_64 exercises the arithmetic, and there a mis-keyed dedup would show as a wrong
## value rather than as a duplicate symbol.
scale := fn(g : u64, x : u64) -> u64 {
  up := 3.5
  down := 1.25
  return g(x) + g(x) + u64(up) - u64(down)
}
main := fn() -> u64 {
  c := 10
  f := fn(n : u64) -> u64 { return n + c }
  return scale(f, 10)
}
