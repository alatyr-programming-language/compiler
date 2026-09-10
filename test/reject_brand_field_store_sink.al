## e2e — Issue #299 / Types §4.2-§4.3 + §5.4:395-400. A struct-FIELD STORE is a value sink like any
## other: `s.x = b` writes a SIBLING brand into a slot declared `A`, and §5.4 gives two siblings over
## one block no conversion into each other at all. The refusal PR #593 landed reached the annotated
## binding, the `=` re-assignment of a name, the call argument, the declared result, the early
## `return`, the binary operator, the struct-literal FIELD and the brand constructor — but not the
## field store, because that write is judged on a PLACE path and its own conformance check ends in
## `tag_compat`, where every tag-8 brand is compatible with every other. While it was open, `s.x = b`
## was the standing way around every one of those refusals.
##
## Four-backend witness: the rule is decided in `check` and is TARGET-INDEPENDENT, so the per-file
## manifest carries an x86_64, aarch64, riscv64 and wasm row for this source and each must be a
## refusal, not only the x86 one.
##
## The value is built with `A(4)` / `B(2)` on purpose. Written as an annotated integer literal
## (`b : B = 2`) the program comes back refused by a DIFFERENT defect, #563, which fires before the
## sink is judged and masks it; such a fixture would prove nothing about brand identity.
##
## Failure-first: on the parent compiler (`main` b61bfa4) this program checked at rc 0, built at
## rc 0 and RAN TO 2 — the sibling `B(2)` laundered into the `A`-typed field and read back out.
A := brand(u64)
B := brand(u64)

S := struct { x : A }

main := fn() -> u64 {
  b : B = B(2)
  mut s := S(x = A(4))
  s.x = b
  return u64(s.x)
}
