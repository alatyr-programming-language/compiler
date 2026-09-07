## issue #465 — three more RIGHT-HAND SIDES of an ASSIGNMENT to a struct's ENUM FIELD (`h.t = <rhs>`)
## on x86_64. PR #463 (issue #461) taught `emit_enum_assign` the enum PLACE and the enum-returning
## CALL; every other non-literal value still fell into its `_ => {}` wildcard, which emitted NO
## INSTRUCTION while `emit_local_field_agg_store` returned `true`. The store was DROPPED and the field
## kept whatever the struct LITERAL had put there: a clean compile answering stale.
##
##   h.t = s.t                       an enum FIELD of another struct
##   h.t = xs[0]                     an enum ARRAY ELEMENT
##   h.t = if c { … } else { … }     a BRANCH value
##
## Every observable gets its OWN exit code, so the number names which half failed. No code is reused
## for two different meanings:
##   51 / 55 / 61 / 65 / 69 / 73 / 77 / 85 / 89 / 93   the STALE variant the struct literal wrote
##   52 / 56 / 62 / 66 / 70 / 74 / 78 / 86 / 90 / 94   a THIRD variant — neither stale nor assigned
##   53 / 57 / 63 / 67 / 71 / 75 / 79 / 87 / 91 / 95   no variant at all (garbage / zero discriminant)
##   54 / 58 / 64 / 68 / 72 / 76 / 80 / 88 / 92 / 96   the field AFTER the enum was clobbered
##   59 / 60 / 97 / 98 / 99                            the right variant but a PAYLOAD word was lost
##   81 / 82 / 83 / 84                                 a CONTROL that already worked stopped working
## All pass -> 42. Parent 8b422be exits 51.
##
## The payload-carrying `Pay` cases exist because the enum is THREE words wide: a one-word store would
## keep the discriminant and silently drop both payload words, which is how the neighbouring defects
## in this class actually failed.
##
## x86-only (`run_x86`): aarch64 and riscv64 have no lowering for the field-ASSIGNMENT shape and trap
## loudly, asserted as the EXACT status in scripts/e2e.sh; the wasm enum-field READ is issue #449, so
## there is no fourth backend to agree with yet. The corpus manifest records all four columns anyway.

Tag := enum { Red, Green, Blue }
Pay := enum { A(u64), B(u64, u64) }

Holder := struct { t : Tag, n : u64 }
Boxed := struct { p : Pay, n : u64 }
Src := struct { t : Tag, m : u64 }
WSrc := struct { p : Pay, m : u64 }

## FORM 1 — the RHS is an enum FIELD of another struct LOCAL.
from_field := fn() -> u64 {
  s := Src(t = Tag.Green, m = 3)
  mut h := Holder(t = Tag.Red, n = 7)
  h.t = s.t
  x := h.t
  if h.n != 7 { return 54 }
  if x == Tag.Red { return 51 }
  if x == Tag.Blue { return 52 }
  if x == Tag.Green { return 0 }
  return 53
}

## FORM 1, WIDER THAN ONE WORD — a three-word `Pay` field copied out of another struct. A one-word
## store keeps the discriminant and loses both payload words.
from_field_wide := fn() -> u64 {
  s := WSrc(p = Pay.B(5, 6), m = 3)
  mut b := Boxed(p = Pay.A(1), n = 9)
  b.p = s.p
  if b.n != 9 { return 58 }
  match b.p {
    Pay::A(v) => { 55 }
    Pay::B(v, w) => { if v != 5 { 59 } else { if w != 6 { 60 } else { 0 } } }
  }
}

## FORM 1, BY-REFERENCE BASE — §8 piece 3 passes the source struct by reference, so its enum field is
## read through the block POINTER rather than out of this frame.
from_ref_field := fn(s : Src) -> u64 {
  mut h := Holder(t = Tag.Red, n = 7)
  h.t = s.t
  x := h.t
  if h.n != 7 { return 64 }
  if x == Tag.Red { return 61 }
  if x == Tag.Blue { return 62 }
  if x == Tag.Green { return 0 }
  return 63
}

## FORM 2 — the RHS is an enum ARRAY ELEMENT.
from_elem := fn() -> u64 {
  xs := [Tag.Green, Tag.Blue]
  mut h := Holder(t = Tag.Red, n = 7)
  h.t = xs[0]
  x := h.t
  if h.n != 7 { return 68 }
  if xs[1] == Tag.Blue { } else { return 67 }
  if x == Tag.Red { return 65 }
  if x == Tag.Blue { return 66 }
  if x == Tag.Green { return 0 }
  return 67
}

## FORM 2, WIDER THAN ONE WORD — element 1 of a `Pay` array, so both the element stride and the
## payload width have to be right.
from_elem_wide := fn() -> u64 {
  ws := [Pay.A(1), Pay.B(5, 6)]
  mut b := Boxed(p = Pay.A(1), n = 9)
  b.p = ws[1]
  if b.n != 9 { return 72 }
  match b.p {
    Pay::A(v) => { 69 }
    Pay::B(v, w) => { if v != 5 { 97 } else { if w != 6 { 98 } else { 0 } } }
  }
}

## FORM 3 — the RHS is a BRANCH value whose branches are variant LITERALS.
from_if_lit := fn(c : bool) -> u64 {
  mut h := Holder(t = Tag.Red, n = 7)
  h.t = if c { Tag.Green } else { Tag.Blue }
  x := h.t
  if h.n != 7 { return 76 }
  if x == Tag.Red { return 73 }
  if x == Tag.Blue { return 74 }
  if x == Tag.Green { return 0 }
  return 75
}

## FORM 3, WIDER THAN ONE WORD — a payload-carrying branch value.
from_if_wide := fn(c : bool) -> u64 {
  mut b := Boxed(p = Pay.A(1), n = 9)
  b.p = if c { Pay.B(5, 6) } else { Pay.A(1) }
  if b.n != 9 { return 80 }
  match b.p {
    Pay::A(v) => { 77 }
    Pay::B(v, w) => { if v != 5 { 99 } else { if w != 6 { 78 } else { 0 } } }
  }
}

## FORM 3, BRANCHES THAT ARE ENUM PLACES rather than literals — the branch deliverer has to reach the
## same words writer, not refuse the shape.
from_if_place := fn(c : bool) -> u64 {
  g := Tag.Green
  r := Tag.Blue
  mut h := Holder(t = Tag.Red, n = 7)
  h.t = if c { g } else { r }
  x := h.t
  if h.n != 7 { return 88 }
  if x == Tag.Red { return 85 }
  if x == Tag.Blue { return 86 }
  if x == Tag.Green { return 0 }
  return 87
}

## FORM 3, THE `match` SPELLING of the same branch value.
from_match := fn(k : u64) -> u64 {
  mut h := Holder(t = Tag.Red, n = 7)
  h.t = match k { 1 => { Tag.Green } _ => { Tag.Blue } }
  x := h.t
  if h.n != 7 { return 92 }
  if x == Tag.Red { return 89 }
  if x == Tag.Blue { return 90 }
  if x == Tag.Green { return 0 }
  return 91
}

## An enum TUPLE COMPONENT, measured on the same writer — the field resolver reaches it too.
from_tuple := fn() -> u64 {
  tp := (Tag.Green, 3)
  mut h := Holder(t = Tag.Red, n = 7)
  h.t = tp.0
  x := h.t
  if h.n != 7 { return 96 }
  if x == Tag.Red { return 93 }
  if x == Tag.Blue { return 94 }
  if x == Tag.Green { return 0 }
  return 95
}

## CONTROL — a variant LITERAL right-hand side already worked and must keep working.
lit_rhs := fn() -> u64 {
  mut b := Boxed(p = Pay.A(1), n = 9)
  b.p = Pay.B(5, 6)
  if b.n != 9 { return 81 }
  match b.p {
    Pay::A(v) => { 81 }
    Pay::B(v, w) => { if v != 5 { 81 } else { if w != 6 { 81 } else { 0 } } }
  }
}

## CONTROL — the enum PLACE right-hand side PR #463 fixed must stay fixed.
place_rhs := fn(v : Tag) -> u64 {
  e := Tag.Green
  mut h := Holder(t = Tag.Red, n = 7)
  h.t = e
  mut h2 := Holder(t = Tag.Red, n = 7)
  h2.t = v
  if h.t == Tag.Green { } else { return 82 }
  if h2.t == Tag.Green { } else { return 82 }
  return 0
}

## CONTROL — the enum-returning CALL right-hand side PR #463 fixed must stay fixed.
green := fn() -> Tag { Tag.Green }
wide := fn() -> Pay { Pay.B(5, 6) }
call_rhs := fn() -> u64 {
  mut h := Holder(t = Tag.Red, n = 7)
  h.t = green()
  mut b := Boxed(p = Pay.A(1), n = 9)
  b.p = wide()
  if h.t == Tag.Green { } else { return 83 }
  match b.p {
    Pay::A(v) => { 83 }
    Pay::B(v, w) => { if v != 5 { 83 } else { if w != 6 { 83 } else { 0 } } }
  }
}

## CONTROL — binding the same right-hand sides to a LOCAL (never through a field) already worked.
plain_binds := fn() -> u64 {
  s := Src(t = Tag.Green, m = 3)
  a := s.t
  xs := [Tag.Green, Tag.Blue]
  b := xs[0]
  if a == Tag.Green { } else { return 84 }
  if b == Tag.Green { } else { return 84 }
  return 0
}

main := fn() -> u64 {
  r1 := from_field()
  if r1 != 0 { return r1 }
  r2 := from_field_wide()
  if r2 != 0 { return r2 }
  r3 := from_ref_field(Src(t = Tag.Green, m = 3))
  if r3 != 0 { return r3 }
  r4 := from_elem()
  if r4 != 0 { return r4 }
  r5 := from_elem_wide()
  if r5 != 0 { return r5 }
  r6 := from_if_lit(true)
  if r6 != 0 { return r6 }
  r7 := from_if_wide(true)
  if r7 != 0 { return r7 }
  r8 := from_if_place(true)
  if r8 != 0 { return r8 }
  r9 := from_match(1)
  if r9 != 0 { return r9 }
  r10 := from_tuple()
  if r10 != 0 { return r10 }
  r11 := lit_rhs()
  if r11 != 0 { return r11 }
  r12 := place_rhs(Tag.Green)
  if r12 != 0 { return r12 }
  r13 := call_rhs()
  if r13 != 0 { return r13 }
  r14 := plain_binds()
  if r14 != 0 { return r14 }
  42
}
