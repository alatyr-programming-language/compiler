## e2e — Issue #299 / Types §4.2-§4.3 + §5.4:395-400. This is the COMPOSITION of two landed slices,
## and the only permanent witness either of them has for it. A module-level value declaration
## annotated with an ARRAY is judged by two mechanisms that landed separately: the `check_decl` hook
## finds the sink at all — a module binding carries no dedicated type field, so it is not one of
## `check_stmts`' value sinks and its `: T` is recovered from the source at the DECL site — and the
## tag-7 element walker takes the `[2]A` annotation apart and judges each element against the
## element type. Neither slice gated this shape on its own: the element walker's own hook sites are
## all inside a fn body, and before it existed a tag-7 declared type reached the scalar judge, which
## answers 0 for an array annotation and so refused nothing.
##
## That is why this fixture is TRACKED rather than a row in the private `issue299` matrix. The
## four-backend claim for a `check`-phase brand refusal is already carried by
## `test/reject_brand_sibling_sink.al` and `test/reject_brand_module_global_sink.al`, and this file
## adds nothing to it. What it adds is an oracle row for a COMPOSITION — the class that has broken
## silently in this repository before (#528) — so that a later refactor of the dispatcher cannot
## regress it without moving a line in `scripts/corpus.manifest`. A matrix row lives in a scratch
## directory, is invisible to the oracle, and would let exactly that regression through.
##
## Four-backend witness: the rule is decided in `check` and is TARGET-INDEPENDENT, so the per-file
## manifest carries an x86_64, aarch64, riscv64 and wasm row for this source and each must be a
## refusal, not only the x86 one.
##
## The elements are built with `B(1)` / `B(2)` on purpose. Written as annotated integer literals they
## would be judged by §9.1/§9.2's literal path — class B1U, which this refusal deliberately never
## touches — so such a fixture would prove nothing about brand identity.
##
## No runtime value is asserted here and none could be: this is a reject fixture, so the fixed
## compiler never reaches run, and on a compiler that accepts it the value would be all-zero anyway
## for the separate reason recorded in #674.
A := brand(u64)
B := brand(u64)

G : [2]A = [B(1), B(2)]

main := fn() -> u64 { return u64(G[0]) }
