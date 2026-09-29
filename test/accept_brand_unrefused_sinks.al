## e2e — Issue #299, the COVERAGE reminder, now with NOTHING numbered. This program is VALID: every
## crossing it used to lock in as accepted is closed, and it keeps the legal spelling of each so the
## sinks it named stay exercised beside their refusals.
##
## The refusal reaches every sink the checker's LIVE path reaches — the annotated binding, a `=`
## re-assignment, a direct/UFCS call argument, the declared
## result, an early `return`, a binary operator (including an `if`-expression's condition), a
## struct-literal FIELD, a brand constructor fed another brand, the struct-field STORE, a value read
## out of a branded FIELD, EVERY component of an enum-variant payload, every ELEMENT of an array
## literal at a `[N]T` / `[T; N]` sink, a module-level annotated value declaration, and a DECLARED
## RESULT whose type is a fixed array.
##
## SEVEN entries left this list, and the lesson of the list is the reason this fixture is kept. The
## last was item 1, `F.P(b, 7)` and `F.P(A(1), c)` — a MULTI-COMPONENT variant payload — listed because
## `FieldDecl` records one type span for the whole payload list; the declaration's own `(T0, T1, …)`
## text still carries the rest, and `sema_enum_payload_ty` reads component `k` from there
## (`reject_brand_payload_component_sink`). Before it, `mk := fn() -> [A; 2] {` and the ARRAY
## PARAMETER beside it were never on the list at all: both were found because the census instrument
## was REPAIRED (#679) and started looking. The list was what someone measured, never the boundary of
## the class — which is why `scripts/brand_census.sh planted` exists.

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

main := fn() -> u64 {
  b : B = B(2)
  c : C = C(3)

  ## The multi-component payload, written the legal way: the values item 1 used to carry (2 + 7 and
  ## 1 + 3) through `A(…)` and a plain `u64`, so `fv` and `gv` below keep their answers.
  f1 := F.P(A(2), 7)
  f2 := F.P(A(1), 3)

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
