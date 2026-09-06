## e2e — issue #448: on aarch64 and riscv64 a `match` over an enum PLACE answered the WILDCARD while the
## same `match` over an enum LOCAL was fail-loud. The refusal was never the mechanism: both backends do
## dispatch `match <struct local>.<enum field>` on the field's frame words. What was wrong is what the
## field HELD. §8 piece 3 passes an enum BY REFERENCE, so an enum PARAM's frame slot carries a POINTER
## to the caller's {disc, payload…} block; the struct-literal field store emitted that slot as one scalar
## word, so `h := Holder(t = v)` wrote an ADDRESS where the discriminant belongs. The dispatch then
## compared the address against 0, 1, 2, matched no arm, and handed back the wildcard — a clean binary,
## a normal exit, the wrong number. The same one-word store dropped every PAYLOAD word of an enum LOCAL
## wider than one word, so a matched arm read its payload out of a slot nothing had written.
##
## Every failure is read with its OWN exit code, so the number a broken tree returns names the mechanism
## instead of merely denying the right answer:
##   51 = the wildcard won (no arm matched)      — the pointer-as-discriminant store;
##   50 = the FIRST arm won                      — a discriminant that happens to equal arm 0;
##   56 = the no-wildcard fallback delivered 0;
##   63/64 = a payload arm matched but its payload word was never written (the truncating store).
##
## Measured with the cross binutils under qemu. Parent 5eb6739: x86_64 42, aarch64 51, riscv64 51.
## This tree: 42 on all three. wasm traps (134) — it has no lowering for this shape at all (issue #449).
Tag := enum { Red, Green, Blue }
Holder := struct { t : Tag }
Sized := struct { t : Tag, n : u64 }
Pay := enum { A(u64), B(u64) }
Boxed := struct { p : Pay }

## the discriminant-0 variant is written FIRST: a pointer-as-discriminant store matches no arm at all.
in_order := fn(v : Tag) -> u64 {
  h := Holder(t = v)
  match h.t { Red => 11, Green => 22, Blue => 33, _ => 91 }
}

## `Green` is written FIRST, so a discriminant that lands on 0 takes THIS arm for every scrutinee.
reordered := fn(v : Tag) -> u64 {
  h := Holder(t = v)
  match h.t { Green => 22, Red => 11, Blue => 33, _ => 91 }
}

## no wildcard: an unmatched arm chain delivers the backend's no-arm fallback instead of trapping here.
no_wild := fn(v : Tag) -> u64 {
  h := Holder(t = v)
  match h.t { Red => 11, Green => 22, Blue => 33 }
}

## the enum field must not displace the scalar field that follows it.
sized := fn(v : Tag) -> u64 {
  s := Sized(t = v, n = 7)
  if s.n != 7 { return 70 }
  match s.t { Red => 11, Green => 22, Blue => 33, _ => 91 }
}

## the struct is built in a CALLEE and returned: the return-register field store is the same one-word site.
mk := fn(v : Tag) -> Holder { Holder(t = v) }
via_return := fn(v : Tag) -> u64 {
  h := mk(v)
  match h.t { Red => 11, Green => 22, Blue => 33, _ => 91 }
}

## a field read feeding the next field write — correct only once the first field holds a discriminant.
refeed := fn(v : Tag) -> u64 {
  h := Holder(t = v)
  k := Holder(t = h.t)
  match k.t { Red => 11, Green => 22, Blue => 33, _ => 91 }
}

## a PAYLOAD-carrying enum param: both the discriminant and the payload word must reach the field.
pay_param := fn(x : Pay) -> u64 {
  b := Boxed(p = x)
  match b.p { A(v) => v, B(v) => v + 100, _ => 91 }
}

## a PAYLOAD-carrying enum LOCAL: word 0 landed, the payload word was dropped.
pay_local := fn() -> u64 {
  e := Pay.B(5)
  b := Boxed(p = e)
  match b.p { A(v) => v, B(v) => v + 100, _ => 91 }
}

## CONTROL — a ONE-WORD enum local into the same field already answered correctly, and must keep doing so
## on the identical emitted text.
unit_local := fn() -> u64 {
  e := Tag.Green
  h := Holder(t = e)
  match h.t { Red => 11, Green => 22, Blue => 33, _ => 91 }
}

## CONTROL — an enum-RETURNING call into the same field already answered correctly.
green := fn() -> Tag { Tag.Green }
from_call := fn() -> u64 {
  h := Holder(t = green())
  match h.t { Red => 11, Green => 22, Blue => 33, _ => 91 }
}

main := fn() -> u64 {
  a := in_order(Tag.Green)
  if a == 11 { return 50 }            ## the FIRST arm won
  if a == 91 { return 51 }            ## no arm matched: the wildcard won
  if a != 22 { return 52 }

  b := reordered(Tag.Red)
  if b == 22 { return 53 }            ## the FIRST arm won
  if b == 91 { return 54 }            ## no arm matched: the wildcard won
  if b != 11 { return 55 }

  c := no_wild(Tag.Blue)
  if c == 0 { return 56 }             ## no arm matched: the no-arm fallback
  if c == 11 { return 57 }            ## the FIRST arm won
  if c != 33 { return 58 }

  if sized(Tag.Green) != 22 { return 59 }
  if via_return(Tag.Green) != 22 { return 60 }
  if refeed(Tag.Green) != 22 { return 61 }

  p := pay_param(Pay.B(5))
  if p == 100 { return 63 }           ## arm B matched, payload word never written
  if p != 105 { return 65 }

  q := pay_local()
  if q == 100 { return 64 }           ## arm B matched, payload word never written
  if q != 105 { return 66 }

  if unit_local() != 22 { return 67 }
  if from_call() != 22 { return 68 }

  ## every variant of the direct-field shape, so a store that happens to be right for one discriminant
  ## is not mistaken for a working one.
  if in_order(Tag.Red) != 11 { return 80 }
  if in_order(Tag.Blue) != 33 { return 81 }
  if reordered(Tag.Green) != 22 { return 82 }
  if reordered(Tag.Blue) != 33 { return 83 }
  if pay_param(Pay.A(9)) != 9 { return 84 }
  42
}
