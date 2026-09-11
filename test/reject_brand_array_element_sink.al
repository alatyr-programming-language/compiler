## e2e — Issue #299 / Types §4.2-§4.3 + §5.4:395-400. An ARRAY-LITERAL ELEMENT is a value sink like
## every other: `xs : [2]A = [b, b]` writes a SIBLING brand into two slots declared `A`, and §5.4
## gives two siblings over one block no conversion into each other at all. The refusals PR #593 and
## PR #650 landed reached fourteen sinks — the annotated binding, the `=` re-assignment, the call
## argument, the declared result, the early `return`, the binary operator, the struct-literal FIELD,
## the brand constructor, the struct-field STORE and the value read out of a branded FIELD among
## them — but not this one, and the reason was never the classifier. `resolve_ty` answers tag 7 for
## the WHOLE `[2]A` annotation and extracts no element type, so there was no declared sink type for
## the classifier to judge an element against. The element type is now extracted beside the sink and
## every element goes to the SAME `sema_brand_class` all fourteen closed sinks already use.
##
## The LEGAL control sits in this file on purpose, one line above the crossing. An array literal
## whose elements are `A(...)` is exactly the explicit form §4.2 prescribes and must stay accepted,
## and the `check` row on this fixture pins the refusal's LINE — so a refusal that fired on the
## control instead would FAIL that row rather than pass it. The running control lives in
## `test/accept_brand_unrefused_sinks.al`, which keeps a legal `[2]A` literal beside the sinks that
## are still open and still returns its value.
##
## Both array-annotation spellings this tree writes reach the same extractor: `[T; N]` (`src/`,
## `lib/`) and `[N]T` (`test/view_var_copy.al`, `test/slice_param_copy_local.al`). Neither of those
## two brandless fixtures moves — a `[4]u8` of integer literals declares no brand at all, and the
## whole judgement is skipped for a program with no brand declaration.
##
## Four-backend witness: the rule is decided in `check` and is TARGET-INDEPENDENT, so the per-file
## manifest carries an x86_64, aarch64, riscv64 and wasm row for this source and each must be a
## refusal, not only the x86 one.
##
## The value is built with `A(4)` / `B(2)` on purpose. Written as an annotated integer literal
## (`b : B = 2`) the program comes back refused by a DIFFERENT defect, #563, which fires before the
## sink is judged and masks it; such a fixture would prove nothing about brand identity. An integer
## literal element (`xs : [2]A = [1, 2]`) is deliberately NOT refused either: Types §9.1/§9.2 give a
## literal its type from context, so that is class B1U and belongs to #563, not here.
##
## Failure-first: on the parent compiler (`main` 53e48e0) this program checked at rc 0, built at
## rc 0 and RAN TO 7 — the sibling `B(2)` laundered into the `A`-typed array and read back out.
A := brand(u64)
B := brand(u64)

main := fn() -> u64 {
  b : B = B(2)
  ok : [2]A = [A(4), A(5)]
  xs : [2]A = [b, b]
  return u64(xs[0]) + u64(ok[1])
}
