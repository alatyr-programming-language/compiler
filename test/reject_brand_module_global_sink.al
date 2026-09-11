## e2e — Issue #299 / Types §4.2-§4.3 + §5.4:395-400. A MODULE-LEVEL value declaration is a value
## sink like any other: `G : A = B(1)` writes a SIBLING brand into a module binding declared `A`,
## and §5.4 gives two siblings over one block no conversion into each other at all. The refusal
## PR #593 landed reached the annotated LOCAL binding, the `=` re-assignment, the call argument, the
## declared result, the early `return`, the binary operator, the struct-literal FIELD and the brand
## constructor, and PR #650 added the struct-field store and the branded-field read — but not this
## one, because a module binding carries no dedicated type field. It is not one of `check_stmts`'
## hooked value sinks at all: its `: T` is recovered from the source spelling at the DECL site, the
## way `global_type_span` recovers it for the global-reassign sink, and the §3.1 assignability
## checks that already run there compare LITERAL tags, never two typed values.
##
## Four-backend witness: the rule is decided in `check` and is TARGET-INDEPENDENT, so the per-file
## manifest carries an x86_64, aarch64, riscv64 and wasm row for this source and each must be a
## refusal, not only the x86 one.
##
## The value is built with `B(1)` on purpose. Written as an annotated integer literal (`G : A = 1`)
## it is not a conversion between two typed values at all — §9.1 gives the literal its type from
## context and §9.2 lets an annotation refine it — so that spelling is accepted deliberately and is
## kept as a control in `test/accept_brand_unrefused_sinks.al`; a fixture written that way would
## prove nothing about brand identity.
##
## Failure-first: on the parent compiler (`main` 53e48e0) this program checked at rc 0, built at
## rc 0 and RAN TO 1 — the sibling `B(1)` laundered into the `A`-typed module binding and read back
## out.
A := brand(u64)
B := brand(u64)

G : A = B(1)

main := fn() -> u64 {
  return u64(G)
}
