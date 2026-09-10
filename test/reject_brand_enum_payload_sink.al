## e2e — Issue #299 / Types §4.2-§4.3 + §5.4:395-400. An ENUM-VARIANT PAYLOAD is a value sink like
## any other: `E.One(b)` writes a SIBLING brand into a component declared `A`, and §5.4 gives two
## siblings over one block no conversion into each other at all. The refusal PR #593 landed reached
## the annotated binding, the `=` re-assignment, the call argument, the declared result, the early
## `return`, the binary operator, the struct-literal FIELD and the brand constructor; PR #650 added
## the struct-field STORE and the branded field READ. The variant payload was left out on the stated
## belief that the sink type "does not exist in the AST yet" — which is true only of the components
## AFTER the first. `src/ast.al`'s `FieldDecl` carries ONE `ts`/`tl` pair per variant and
## `src/parser.al` fills it under `if marity == 0`, so an ARITY-1 variant's declared payload type IS
## recorded, and it is the very span the arity verdict (Issue #513) already reads its count from.
##
## Four-backend witness: the rule is decided in `check` and is TARGET-INDEPENDENT, so the per-file
## manifest carries an x86_64, aarch64, riscv64 and wasm row for this source and each must be a
## refusal, not only the x86 one.
##
## The value is built with `A(4)` / `B(2)` on purpose. Written as an annotated integer literal
## (`b : B = 2`) the program comes back refused by a DIFFERENT defect, #563, which fires before the
## sink is judged and masks it; such a fixture would prove nothing about brand identity.
##
## Scope: ARITY 1 only. A variant of arity >= 2 keeps no type for its components 2..n at all — one
## span for the whole list — so `F.P(A(1), b)` stays accepted and is locked as an open sink in
## `test/accept_brand_unrefused_sinks.al`. Closing it needs `FieldDecl` to grow a per-component type
## list, which is not emission-neutral; that residual stays on #299.
##
## Failure-first: on the parent compiler (`main` 53e48e0) this program checked at rc 0, built at
## rc 0 and RAN TO 2 — the sibling `B(2)` laundered into the `A`-typed payload and read back out.
A := brand(u64)
B := brand(u64)

E := enum { One(A), Two }

main := fn() -> u64 {
  b : B = B(2)
  e := E.One(b)
  ev := match e { E::One(v) => { u64(v) } E::Two => { 0 } }
  return ev
}
