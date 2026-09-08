## e2e — Issue #299, the COVERAGE reminder. This program is INVALID under Types §4.2/§4.3 + §5.4:
## every crossing below is an implicit brand conversion. It is accepted today, and this fixture
## deliberately locks that in so nobody can read the landed refusal as complete.
##
## The refusal reaches every sink the checker's LIVE path reaches — the annotated binding, a `=`
## re-assignment, a direct/UFCS call argument, the declared result, an early `return`, a binary
## operator (including an `if`-expression's condition), a struct-literal FIELD, and a brand
## constructor fed another brand. These five sinks it does NOT reach, each for a stated reason:
##
##   1. `G : A = B(1)`      — a MODULE-LEVEL value declaration is not one of the checker's hooked
##                            value sinks; its annotation is recovered separately (`global_type_span`).
##   2. `xs : [2]A = [b, b]`— an ARRAY-LITERAL element: `resolve_ty` answers tag 7 for the whole
##                            `[2]A` annotation and the element type is never extracted, so there is
##                            no declared sink type to judge against.
##   3. `E.One(b)`          — an ENUM-VARIANT payload: the parser records no per-component payload
##                            type ("their type against the variant's payload type is DEFERRED"), so
##                            the sink type does not exist in the AST yet.
##   4. `s.x = b`           — a struct-FIELD store: a place-typed assignment, judged by the field
##                            store path rather than by a value sink.
##   5. `fld : u64 = s.x`   — the B1R direction through a FIELD READ: the brand-identity recovery
##                            reads a constructor, a declared callee result and an annotated local,
##                            and a `Field` expression is none of those, so the value's identity is
##                            unknown and the poison-tolerant sink accepts it.
##
## Two more shapes are accepted ON PURPOSE and are not gaps: `u64(c)` composes brand removal with a
## numeric conversion in one `T(v)`, which the pin does not say a single constructor may or may not
## do (so it is not inferred from behaviour here), and an operator mixing a brand with its OWN
## underlying type is the open operator-inheritance design question #299's probe comment records.
##
## When a later unit closes one of these, THIS FIXTURE MUST FAIL and move to a `reject_*` row. That
## is its job. Returns 42 while they are all still open.
##
## RUNS to its value on x86_64 only. The three non-x86 backends implement a scalar core that does not
## lower a brand construction at all, so every brand-declaring program in this tree already traps
## loudly there: `test/accept_ann_brand_and_generic.al` is `run/12` on x86_64 and `run/133 · 133 · 134`
## on aarch64 · riscv64 · wasm in the committed manifest, measured on the PARENT compiler, and these
## rows are the same shape. That is a pre-existing backend-subset limit, not this refusal's doing —
## the four-backend claim this unit owes is that all four surfaces REFUSE an implicit crossing, and
## `test/reject_brand_sibling_sink.al` carries it as `compile/1` on every one of them.
A := brand(u64)
B := brand(u64)
C := brand(u8)

S := struct { x : A }
E := enum { One(A), Two }

## (1) a module-level value declaration annotated `A`, initialized with a sibling `B`.
G : A = B(1)

main := fn() -> u64 {
  b : B = B(2)
  c : C = C(3)

  ## (2) an array-literal element, (3) an enum-variant payload, (4) a struct-field store.
  xs : [2]A = [b, b]
  e := E.One(b)
  mut s := S(x = A(4))
  s.x = b

  ## (5) the brand→raw direction through a field read.
  fld : u64 = s.x

  ev := match e { E::One(v) => { u64(v) } E::Two => { 0 } }

  if u64(G) != 1 { return 1 }
  if u64(xs[0]) != 2 { return 2 }
  if ev != 2 { return 3 }
  if fld != 2 { return 4 }
  if u64(c) != 3 { return 5 }
  return 42
}
