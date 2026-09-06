## issue #461 — an ASSIGNMENT to a struct's ENUM FIELD (`h.t = v`) on x86_64. `emit_enum_assign`
## matched only `Expr::EnumLit`; its wildcard arm emitted NO INSTRUCTION, so the store was DROPPED and
## every later read saw the variant the struct LITERAL had put there. Nothing was refused, nothing
## trapped: a silent wrong value on the reference backend. The mechanism is a dropped store, NOT the
## by-reference-pointer datum of issue #448.
##
## Every observable gets its OWN exit code, so the number names which half failed:
##   51 / 55 / 61 / 68 / 75  the STALE variant the struct literal wrote (the parent's answer)
##   52 / 56 / 62 / 69 / 76  a THIRD variant — neither the stale one nor the assigned one
##   53 / 57 / 63 / 70 / 77  no variant at all (garbage / zero discriminant)
##   54 / 58 / 64 / 71 / 78  the field AFTER the enum was clobbered by an over-wide store
##   65 / 72                 the right arm matched but a PAYLOAD word was lost
##   85 / 86 / 87            the same dropped store through the enum-VAR element of an array literal
##   81 / 82 / 83 / 84       a CONTROL that already worked stopped working
## All pass -> 42. Parent 5eb6739 exits 51.
##
## x86-only (`run_x86`): on aarch64 and riscv64 this shape is a fail-loud trap today, and the wasm
## field READ is issue #449, so there is no fourth backend to agree with yet. The corpus manifest
## records all four columns for this file regardless.

Tag := enum { Red, Green, Blue }
Pay := enum { A(u64), B(u64, u64) }

Holder := struct { t : Tag, n : u64 }
Boxed := struct { p : Pay, n : u64 }

green := fn() -> Tag { Tag.Green }
wide := fn() -> Pay { Pay.B(5, 6) }

## the assigned value is a by-reference enum PARAM (§8 piece 3), read back through `==`
from_param := fn(v : Tag) -> u64 {
  mut h := Holder(t = Tag.Red, n = 7)
  h.t = v
  x := h.t
  if h.n != 7 { return 54 }
  if x == Tag.Red { return 51 }
  if x == Tag.Blue { return 52 }
  if x == Tag.Green { return 0 }
  return 53
}

## the assigned value is an enum LOCAL (its slot IS the block), read back through `==`
from_local := fn() -> u64 {
  e := Tag.Green
  mut h := Holder(t = Tag.Red, n = 7)
  h.t = e
  x := h.t
  if h.n != 7 { return 58 }
  if x == Tag.Red { return 55 }
  if x == Tag.Blue { return 56 }
  if x == Tag.Green { return 0 }
  return 57
}

## the same param assignment read back through `match` rather than `==`
via_match := fn(v : Tag) -> u64 {
  mut h := Holder(t = Tag.Red, n = 7)
  h.t = v
  if h.n != 7 { return 64 }
  match h.t { Tag::Red => { 61 } Tag::Blue => { 62 } Tag::Green => { 0 } }
}

## a PAYLOAD-CARRYING enum, three words wide, assigned from a by-reference PARAM: a one-word store
## would keep the discriminant and drop both payload words.
wide_param := fn(x : Pay) -> u64 {
  mut b := Boxed(p = Pay.A(1), n = 9)
  b.p = x
  if b.n != 9 { return 71 }
  match b.p {
    Pay::A(v) => { 68 }
    Pay::B(v, w) => { if v == 5 { if w == 6 { 0 } else { 65 } } else { 65 } }
  }
}

## the same wide enum assigned from a LOCAL
wide_local := fn() -> u64 {
  x := Pay.B(5, 6)
  mut b := Boxed(p = Pay.A(1), n = 9)
  b.p = x
  if b.n != 9 { return 78 }
  match b.p {
    Pay::A(v) => { 75 }
    Pay::B(v, w) => { if v == 5 { if w == 6 { 0 } else { 72 } } else { 72 } }
  }
}

## the same wide enum assigned from an enum-returning CALL (its words arrive in the return registers)
wide_call := fn() -> u64 {
  mut b := Boxed(p = Pay.A(1), n = 9)
  b.p = wide()
  if b.n != 9 { return 70 }
  match b.p {
    Pay::A(v) => { 69 }
    Pay::B(v, w) => { if v == 5 { if w == 6 { 0 } else { 63 } } else { 63 } }
  }
}

## CONTROL — assigning a variant LITERAL to the field already worked and must keep working
lit_rhs := fn() -> u64 {
  mut b := Boxed(p = Pay.A(1), n = 9)
  b.p = Pay.B(5, 6)
  if b.n != 9 { return 81 }
  match b.p {
    Pay::A(v) => { 81 }
    Pay::B(v, w) => { if v == 5 { if w == 6 { 0 } else { 81 } } else { 81 } }
  }
}

## CONTROL — building the struct with the wanted variant instead of assigning it afterwards
ctor_lit := fn() -> u64 {
  h := Holder(t = Tag.Green, n = 7)
  x := h.t
  if h.n != 7 { return 82 }
  if x == Tag.Green { return 0 }
  return 82
}

## CONTROL — building the struct from an enum-returning CALL (payload-free, the shape #462 records
## as already correct on x86_64)
ctor_call := fn() -> u64 {
  h := Holder(t = green(), n = 7)
  x := h.t
  if h.n != 7 { return 83 }
  if x == Tag.Green { return 0 }
  return 83
}

## CONTROL — an enum LOCAL bound straight from a call, never through a field
plain_local := fn() -> u64 {
  e := green()
  if e == Tag.Green { return 0 }
  return 84
}

## The SAME writer's other silent caller: an enum-VAR ELEMENT of an array literal (`[e, Tag.Blue]`)
## reached the identical wildcard arm and stored nothing, so element 0 read whatever the slot held.
arr_elem_var := fn() -> u64 {
  e := Tag.Green
  xs := [e, Tag.Blue]
  x := xs[0]
  if xs[1] == Tag.Blue { } else { return 87 }
  if x == Tag.Red { return 85 }
  if x == Tag.Blue { return 86 }
  if x == Tag.Green { return 0 }
  return 87
}

main := fn() -> u64 {
  r1 := from_param(Tag.Green)
  if r1 != 0 { return r1 }
  r2 := from_local()
  if r2 != 0 { return r2 }
  r3 := via_match(Tag.Green)
  if r3 != 0 { return r3 }
  r4 := wide_param(Pay.B(5, 6))
  if r4 != 0 { return r4 }
  r5 := wide_local()
  if r5 != 0 { return r5 }
  r6 := wide_call()
  if r6 != 0 { return r6 }
  r7 := lit_rhs()
  if r7 != 0 { return r7 }
  r8 := ctor_lit()
  if r8 != 0 { return r8 }
  r9 := ctor_call()
  if r9 != 0 { return r9 }
  r10 := plain_local()
  if r10 != 0 { return r10 }
  r11 := arr_elem_var()
  if r11 != 0 { return r11 }
  42
}
