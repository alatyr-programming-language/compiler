## e2e — issue #396: an EXPRESSION-form (bare-arm) `match` in TAIL position whose scrutinee is an enum
## PLACE — a struct FIELD, an enum-array ELEMENT, a struct-field array element, an array-of-struct
## element's field, or a mutable GLOBAL struct's field — must dispatch on the enum DISCRIMINANT.
##
## `emit_return_value`'s tail value-`match` resolved only a plain enum local (`scrut_enum_info`) and a
## mutable enum GLOBAL (`try_global_enum_scrut`). Every other enum place stayed unresolved and fell into
## the INTEGER scrutinee path, where an enum pattern arm carries no scalar literal (`am.lit` is 0): every
## arm compared the scrutinee against 0, so ONLY a variant whose discriminant is 0 could ever match. The
## value-`Expr::Match` renderer and the statement-`match` renderer already materialize these places,
## which is why the two controls at the end measure correct on the parent as well.
##
## The failure is read TWICE, because "the first arm won" and "no arm matched" are DIFFERENT defects and
## a fixture that cannot tell them apart proves nothing about either:
##   * `in_order(Tag.Green)` writes the discriminant-0 variant FIRST, so the parent falls through every
##     arm and lands on the wildcard;
##   * `reordered(Tag.Red)` writes `Green` FIRST, so the parent's compare-against-0 makes the FIRST ARM
##     win and hand back 22 where 11 is due.
## Those two outcomes, and the no-wildcard `movq $0` fallback, each carry their OWN exit code, so the
## number the parent returns names the mechanism instead of merely denying the right answer.
##
## Measured on x86_64: parent (61ca2c2) exits 51, this tree exits 42.
## `run_x86`: aarch64/riscv64/wat have no enum-match lowering at all — an enum-typed scrutinee is a
## fail-loud `brk #0 // unsupported match` there — so this shape is x86_64-only until that is built.
Tag := enum { Red, Green, Blue }
Holder := struct { t : Tag }
Held := struct { items : [Tag; 3] }
Pay := enum { A(u64), B(u64) }
Boxed := struct { p : Pay }

mut G : Holder = Holder(t = Tag.Blue)

## the discriminant-0 variant is written FIRST: a compare-against-0 dispatch matches no arm.
in_order := fn(v : Tag) -> u64 {
  h := Holder(t = v)
  match h.t { Red => 11, Green => 22, Blue => 33, _ => 91 }
}

## `Green` is written FIRST: a compare-against-0 dispatch takes THIS arm for every scrutinee.
reordered := fn(v : Tag) -> u64 {
  h := Holder(t = v)
  match h.t { Green => 22, Red => 11, Blue => 33, _ => 91 }
}

## no wildcard: an unmatched tail value-match delivers the `movq $0` no-arm fallback.
no_wild := fn(v : Tag) -> u64 {
  h := Holder(t = v)
  match h.t { Red => 11, Green => 22, Blue => 33 }
}

elem := fn(i : u64) -> u64 {
  cs := [Tag.Red, Tag.Green, Tag.Blue]
  match cs[i] { Red => 11, Green => 22, Blue => 33, _ => 91 }
}

field_elem := fn(i : u64) -> u64 {
  h := Held(items = [Tag.Red, Tag.Green, Tag.Blue])
  match h.items[i] { Red => 11, Green => 22, Blue => 33, _ => 91 }
}

elem_field := fn(i : u64) -> u64 {
  xs := [Holder(t = Tag.Red), Holder(t = Tag.Green), Holder(t = Tag.Blue)]
  match xs[i].t { Red => 11, Green => 22, Blue => 33, _ => 91 }
}

## the payload must bind through the materialized place, not just the discriminant.
payload := fn(x : Pay) -> u64 {
  b := Boxed(p = x)
  match b.p { A(v) => v, B(v) => v + 100 }
}

global_field := fn() -> u64 {
  match G.t { Red => 11, Green => 22, Blue => 33, _ => 91 }
}

## CONTROL — binding the field to a local first already dispatched correctly on the parent.
bound_local := fn(v : Tag) -> u64 {
  h := Holder(t = v)
  x := h.t
  match x { Red => 11, Green => 22, Blue => 33, _ => 91 }
}

## CONTROL — the braced statement form already dispatched correctly on the parent.
statement_form := fn(v : Tag) -> u64 {
  h := Holder(t = v)
  match h.t { Red => { return 11 } Green => { return 22 } Blue => { return 33 } }
  return 91
}

main := fn() -> u64 {
  a := in_order(Tag.Green)
  if a == 11 { return 50 }            ## the FIRST arm won
  if a == 91 { return 51 }            ## no arm matched: the wildcard won
  if a != 22 { return 52 }            ## wrong for some third reason

  b := reordered(Tag.Red)
  if b == 22 { return 53 }            ## the FIRST arm won
  if b == 91 { return 54 }            ## no arm matched: the wildcard won
  if b != 11 { return 55 }

  c := no_wild(Tag.Blue)
  if c == 0 { return 56 }             ## no arm matched: the `movq $0` fallback
  if c == 11 { return 57 }            ## the FIRST arm won
  if c != 33 { return 58 }

  if elem(1) != 22 { return 60 }
  if field_elem(1) != 22 { return 61 }
  if elem_field(1) != 22 { return 62 }
  if payload(Pay.B(5)) != 105 { return 63 }
  if global_field() != 33 { return 64 }

  if bound_local(Tag.Green) != 22 { return 70 }
  if statement_form(Tag.Green) != 22 { return 71 }

  ## every variant of the direct-field shape, so a dispatch that happens to be right for one
  ## discriminant is not mistaken for a working dispatch.
  if in_order(Tag.Red) != 11 { return 80 }
  if in_order(Tag.Blue) != 33 { return 81 }
  if reordered(Tag.Green) != 22 { return 82 }
  if reordered(Tag.Blue) != 33 { return 83 }
  42
}
