## e2e — Issue #687 / Types §4.2-§4.3 + §5.4:395-400. A DECLARED FUNCTION RESULT whose type is a
## FIXED ARRAY is a value sink like every other: `mk := fn() -> [A; 2] { [B(1), B(2)] }` writes a
## SIBLING brand into two slots declared `A`, and §5.4:395-400 gives two siblings over one block no
## conversion into each other at all — the explicit form is `A(u64(b))`.
##
## This one was not a missing rule and not a missing classifier. The SCALAR spelling of this very
## sink, `fn() -> A { B(1) }`, has been refused since PR #593, and the array-literal ELEMENT walk
## #664 added is alive at an annotated local, a module-level declaration and an arity-1 enum
## payload. It is the COMPOSITION of the two that fell through, and the reason is one truncated
## span: `src/parser.al` captures a result type as its HEAD TOKEN and widens that token for a `::`
## path and a `(…)` tuple but not for a `[…]` array, so `Decl.ret_tl` for `-> [A; 2]` is **1** — the
## single byte `[`. `resolve_ty` answers tag 7 from that first byte, so the dispatcher did descend
## into the element walk; the walk then read an element type out of one byte and got nothing.
## `src/sema.al` now recovers the complete annotation at the brand judgement, leaving the parser's
## `ret_ts`/`ret_tl` pair — which `fn_returns_struct`, `fixed_array_byte_return_len`, `agg_scalar_bad`
## and `fmt` all read — exactly as it is. The two existing recoveries of this same parser property,
## `lower::fixed_array_return_span` and `fmt::skip_balanced_group`, made the same call.
##
## The LEGAL control sits one line above the crossing on purpose. A result built from `A(...)` is
## exactly the explicit form §4.2 prescribes and must stay accepted, and the `check` row pins the
## refusal's LINE — so a refusal that fired on the control instead would FAIL that row rather than
## pass it. `test/accept_brand_array_result_legal.al` is the RUNNING control for the same shape.
##
## Neither function is CALLED, and that is forced rather than tidy: a `[A; 2]` result has no return
## ABI to read it back through, so binding or indexing the call result is a located lower trap
## (`only [u8; N] with 1 <= N <= 16 is supported`). What the parent accepted is therefore the
## DECLARATION — measured below — not a value `main` could print.
##
## Four-backend witness: the rule is decided in `check` and is TARGET-INDEPENDENT, so the per-file
## manifest carries an x86_64, aarch64, riscv64 and wasm row for this source and each must be a
## refusal, not only the x86 one.
##
## The B1R direction of this same sink — `fn() -> [u64; 2] { [A(1), A(2)] }`, a brand into raw slots
## — was accepted on the parent too and is closed by the same recovery; an integer-literal element
## (`fn() -> [A; 2] { [1, 2] }`) is deliberately NOT refused, because Types §9.1/§9.2 give a literal
## its type from context: that is class B1U and belongs to #563.
##
## Failure-first: on the parent compiler (`main` a65e873) this program checked at rc 0 and built at
## rc 0, and the census channel reported `#299 SUMMARY brands=2 prelude=0 sinks=0 hits=0` — zero
## visited sinks at the declaration, so the crossing was not merely unrefused, it was never looked
## at. The program RAN to its value with the sibling-branded result compiled and linked into it.
A := brand(u64)
B := brand(u64)

ok := fn() -> [A; 2] { [A(4), A(5)] }
mk := fn() -> [A; 2] { [B(1), B(2)] }

main := fn() -> u64 { return 0 }
