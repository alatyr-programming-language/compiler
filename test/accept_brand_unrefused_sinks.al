## e2e — Issue #299, the COVERAGE reminder. This program is INVALID under Types §4.2/§4.3 + §5.4:
## the single NUMBERED crossing below is an implicit brand conversion. It is accepted today, and
## this fixture deliberately locks that in so nobody can read the landed refusal as complete.
## Everything that is not numbered is a legal control and must stay accepted.
##
## The refusal reaches every sink the checker's LIVE path reaches — the annotated binding, a `=`
## re-assignment, a direct/UFCS call argument, the declared result, an early `return`, a binary
## operator (including an `if`-expression's condition), a struct-literal FIELD, a brand constructor
## fed another brand, the struct-field STORE, a value read out of a branded FIELD, the payload of an
## ARITY-1 enum variant, every ELEMENT of an array literal at a `[N]T` / `[T; N]` sink and — since
## the MODULE-DECLARATION slice — a module-level annotated value declaration, including the
## composition of the last two. These TWO sinks it does NOT reach, each for a stated reason:
##
##   1. `F.P(b, 7)` and     — a MULTI-COMPONENT enum-variant payload. `src/ast.al`'s `FieldDecl`
##      `F.P(A(1), c)`        carries ONE `ts`/`tl` pair for the whole payload LIST, and
##                            `src/parser.al` fills it under `if marity == 0` — the FIRST component's
##                            type. So components 2..n have no recorded sink type at all, and the one
##                            span that IS recorded cannot be attributed to a component without the
##                            rest of the list beside it. Closing this needs `FieldDecl` to grow a
##                            per-component type list; that is not AST- or emission-neutral and is
##                            residual on #299, not part of the arity-1 slice.
##
##   2. `mk := fn() -> [A; 2] {` — a DECLARED RESULT whose type is a FIXED ARRAY. The scalar
##      `  [B(1), B(2)] }`        spelling `fn() -> A { B(1) }` is refused, and the array-literal
##                                ELEMENT walk is alive at every other sink, so this is the
##                                COMPOSITION of two working parts falling through. `src/parser.al`
##                                captures the result-type HEAD TOKEN and extends it for a `::` path
##                                and a `(…)` tuple but not for a `[…]` array, so `Decl.ret_tl` is
##                                **1** — the single byte `[`. `resolve_ty` still answers tag 7 from
##                                that first byte, the dispatcher does enter the element walk, and
##                                `sema_brand_array_elem_span` then answers {0,0} because a one-byte
##                                span has no element in it. The same truncated span reaches the
##                                early-`return` sink, so `fn() -> [A; 2] { return [B(1), B(2)] }`
##                                falls through the same way.
##
## FIVE entries LEFT this list, and they are the reason this fixture is worth keeping. `s.x = b`,
## the struct-FIELD store, and `fld : u64 = s.x`, the B1R direction through a FIELD READ, were items
## 4 and 5 here; `E.One(b)`, the ARITY-1 enum payload, was item 3, listed on the belief that the
## parser "records no per-component payload type" — accurate only for components 2..n, since an
## arity-1 variant's declared type is exactly what `FieldDecl.ts`/`.tl` holds; `xs : [2]A = [b, b]`,
## the ARRAY-LITERAL element, was item 2, listed because `resolve_ty` answers tag 7 for the whole
## `[2]A` annotation and extracted no element type — a missing SINK TYPE, not a missing rule; and
## `G : A = B(1)`, a MODULE-LEVEL value declaration, was item 1, because a module binding carries no
## dedicated type field, so it is not one of `check_stmts`' hooked value sinks at all and its `: T`
## is recovered from the source at the DECL site (the way `global_type_span` recovers it for the
## global-reassign sink), where the §3.1 assignability checks beside it compare LITERAL tags and
## never two typed values. All five are now refused, each through the same `sema_brand_class` /
## `sema_brand_refuse_class` pair. On the compiler that closed the module declaration this file
## failed at `G : A = B(1)`, which is exactly the job the header below describes. They moved to
## `test/reject_brand_field_store_sink.al`, `test/reject_brand_field_read_sink.al`,
## `test/reject_brand_enum_payload_sink.al`, `test/reject_brand_array_element_sink.al` and
## `test/reject_brand_module_global_sink.al`. The COMPOSITION of the last two — a module-level
## declaration annotated with an array — is refused too and has its own tracked witness,
## `test/reject_brand_module_array_element_sink.al`, because neither slice gated it alone.
##
## A NESTED place path (`s.t.y = b`, a `Stmt::FieldPathAssign`), a field read whose base is not a
## directly known struct root, and an element of a NESTED array annotation (`[[2]A; 2]`, whose inner
## element type the extractor deliberately does not walk) are residual on #299 too, not closed.
##
## Two more shapes are accepted ON PURPOSE and are not gaps: `u64(c)` composes brand removal with a
## numeric conversion in one `T(v)`, which the pin does not say a single constructor may or may not
## do (so it is not inferred from behaviour here), and an operator mixing a brand with its OWN
## underlying type is the open operator-inheritance design question #299's probe comment records.
##
## When a later unit closes this one, THIS FIXTURE MUST FAIL and move to a `reject_*` row. That is
## its job. Returns 42 while it is still open.
##
## RUNS to its value on x86_64 only. The three non-x86 backends implement a scalar core that does not
## lower a brand construction at all, so every brand-declaring program in this tree already traps
## loudly there: `test/accept_ann_brand_and_generic.al` is `run/12` on x86_64 and `run/133 · 133 · 134`
## on aarch64 · riscv64 · wasm in the committed manifest, measured on the PARENT compiler, and these
## rows are the same shape. That is a pre-existing backend-subset limit, not this refusal's doing —
## the four-backend claim each of these units owes is that all four surfaces REFUSE an implicit
## crossing, and `test/reject_brand_sibling_sink.al` carries it as `compile/1` on every one of them.
A := brand(u64)
B := brand(u64)
C := brand(u8)

S := struct { x : A }
E := enum { One(A), Two }
F := enum { P(A, u64), Q }

## The MODULE-LEVEL declaration sink kept as a CONTROL, written the two LEGAL ways: a same-brand
## initializer, and a §9.1/§9.2 integer literal taking its type from the annotation — class B1U,
## which the refusal deliberately never touches. `test/reject_brand_module_global_sink.al` refuses
## the sibling spelling of the first line, so without these two the module rows there would also
## pass if the fence simply refused every annotated module binding. The module-level ARRAY spelling
## has its own pair of fixtures, because its value is not assertable here: see #674 and the header
## of `test/accept_brand_module_array_legal.al`.
G : A = A(1)
GL : A = 5

## (2) the DECLARED RESULT at a FIXED-ARRAY type. Kept at module level and never called, because a
## `[A; 2]` result has no return ABI to read it back through: binding or indexing the call result
## is a located lower trap (`only [u8; N] with 1 <= N <= 16 is supported`), so this crossing cannot
## be asserted from `main` the way the others are. It is still ACCEPTED, BUILT and LINKED — that is
## what this entry locks. `test/accept_brand_array_result_legal.al` carries the legal control.
mk := fn() -> [A; 2] { [B(1), B(2)] }

main := fn() -> u64 {
  b : B = B(2)
  c : C = C(3)

  ## (1) a MULTI-COMPONENT variant payload, in BOTH positions: a sibling `B` where component 1 is
  ## declared `A`, and a `C` over another block where component 2 is declared `u64` (the B1R
  ## direction). Neither is judged, because one recorded span cannot answer for a two-component
  ## list. The ARITY-1 spelling `E.One(...)` right below IS refused now, and `E` is kept here written
  ## the LEGAL way so the contrast is in one file: same enum machinery, one payload, refused.
  f1 := F.P(b, 7)
  f2 := F.P(A(1), c)

  e := E.One(A(9))

  ## The `[2]A` array is kept, written the LEGAL way, so this file still exercises an array-literal
  ## element sink beside the open one: `test/reject_brand_array_element_sink.al` refuses the
  ## implicit form of this exact shape, and this spelling must keep passing here. It is also the
  ## RUNNING control for the `[N]T` annotation spelling the element extractor had to learn — and it
  ## runs because it is a LOCAL; the module-level twin cannot assert a value today (#674).
  xs : [2]A = [A(2), A(2)]

  ## The struct S is kept, written the LEGAL way, so this file still exercises a branded field beside
  ## the open sink: a same-brand store and an EXPLICIT `u64(...)` read are the two spellings
  ## `test/reject_brand_field_store_sink.al` and `test/reject_brand_field_read_sink.al` refuse the
  ## implicit form of, and they must keep passing here.
  mut s := S(x = A(4))
  s.x = A(2)
  fld : u64 = u64(s.x)

  ev := match e { E::One(v) => { u64(v) } E::Two => { 0 } }
  fv := match f1 { F::P(p, q) => { u64(p) + q } F::Q => { 0 } }
  gv := match f2 { F::P(p2, q2) => { u64(p2) + q2 } F::Q => { 0 } }

  if u64(G) != 1 { return 1 }
  if u64(GL) != 5 { return 2 }
  if u64(xs[0]) != 2 { return 3 }
  if ev != 9 { return 4 }
  if fld != 2 { return 5 }
  if u64(c) != 3 { return 6 }
  if fv != 9 { return 7 }
  if gv != 4 { return 8 }
  return 42
}
