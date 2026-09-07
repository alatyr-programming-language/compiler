## issue #462 — a struct field FED BY AN ENUM-RETURNING CALL (`Boxed(p = mk())`) lost the enum, with a
## DIFFERENT wrong number on each backend, and the REFERENCE backend was wrong too:
##
##   x86_64  `emit_struct_assign`'s field loop knows a `StructLit`, an `EnumLit`, a `str`, an aggregate
##           `Var` and an `ArrayLit`. A CALL is none of those, so a `1 + arity`-word enum field fell to
##           the `wsz > 1` ARRAY branch, whose `emit_array_assign` matches only an `ArrayLit` and whose
##           `_ => {}` emitted NOTHING — the call was never even made and the field kept whatever the
##           frame slot happened to hold. A silent wrong value on the backend the others are checked
##           against, which is why this row of the feed matrix outlived #448 / #461 / #465.
##   aarch64 / riscv64
##           `emit_*_store_payload_at`'s scalar fallback stored ONE return register and REPORTED one
##           word, so the discriminant landed, every PAYLOAD word was dropped, and every field after the
##           enum field was written one word too early.
##
## Binding the call's result to a local first (`e := mk()`, then `Boxed(p = e)`) was the workaround and
## is `bound_local` below: it answers correctly on all three backends BEFORE and AFTER, which is what
## pins the expected number without depending on any one backend being right.
##
## Every observable carries its OWN exit code, so the number names the half that failed. Zero is never a
## shared code — it is both this defect's x86_64 answer AND the commonest default — so "a payload word
## read 0" and "a payload word read some other wrong value" are deliberately different numbers:
##   61 / 71 / 82 / 91 / 101      the field AFTER the enum field is wrong (a mis-sized store)
##   81                           the field BEFORE the enum field is wrong (a mis-placed base)
##   52 / 62 / 72 / 83 / 92 / 102 the OTHER variant's arm won
##   53 / 63 / 73 / 84 / 103      the right arm won, payload word 0 read 0 — never delivered
##   54 / 64 / 74 / 85 / 104      the right arm won, payload word 0 read some THIRD value
##   55 / 65 / 86 / 105           the right arm won, payload word 1 read 0
##   56 / 66 / 87 / 106           the right arm won, payload word 1 read some THIRD value
##   57 / 67 / 75 / 88 / 93 / 107 NO arm matched — the wildcard won
##   111 / 112                    a NESTED struct literal's fields after the enum call are mis-placed
## All pass -> 42.
##
## The arms are comma-separated BARE expressions on purpose: a braced arm body over an enum place is
## still fail-loud on aarch64/riscv64, so a `=> { … }` spelling would trap the whole file at 133 there
## and cost this fixture every one of the codes above on the two backends it is measuring.
##
## Measured on parent 43093e5 with the cross binutils under qemu: x86_64 52 (the OTHER arm won — the
## field was never written at all), aarch64 53 and riscv64 53 (the right arm won and payload word 0
## read 0). wasm 134, the #449 refusal, before and after. This tree: 42 / 42 / 42 / 134.

Pay := enum { A(u64), B(u64, u64) }
Tag := enum { Red, Green }

Solo := struct { p : Pay }
Boxed := struct { p : Pay, n : u64 }
Lead := struct { lead : u64, p : Pay, n : u64 }
Holder := struct { t : Tag, n : u64 }
Outer := struct { inner : Boxed, tail : u64 }

mkb := fn() -> Pay { Pay.B(5, 6) }
mka := fn() -> Pay { Pay.A(7) }
green := fn() -> Tag { Tag.Green }

## `B(5, 6)`'s two payload words, told apart word by word and value by value.
chk_b := fn(v : u64, w : u64, z0 : u64, o0 : u64, z1 : u64, o1 : u64) -> u64 {
  if v != 5 {
    if v == 0 { return z0 }
    return o0
  }
  if w != 6 {
    if w == 0 { return z1 }
    return o1
  }
  0
}

## `A(7)`'s single payload word.
chk_a := fn(v : u64, z0 : u64, o0 : u64) -> u64 {
  if v != 7 {
    if v == 0 { return z0 }
    return o0
  }
  0
}

## the issue's own shape: the enum is the WHOLE struct, so nothing but the payload can be wrong
call_solo := fn() -> u64 {
  s := Solo(p = mkb())
  match s.p { A(v) => 52, B(v, w) => chk_b(v, w, 53, 54, 55, 56), _ => 57 }
}

## the same feed with a field AFTER the enum field — a store that reports the wrong width mis-aligns it
call_b := fn() -> u64 {
  b := Boxed(p = mkb(), n = 9)
  if b.n != 9 { return 61 }
  match b.p { A(v) => 62, B(v, w) => chk_b(v, w, 63, 64, 65, 66), _ => 67 }
}

## the OTHER variant of the same enum, ONE payload word — a fix that hardwired one variant's width, or
## one that only ever delivered word 1, would answer here
call_a := fn() -> u64 {
  b := Boxed(p = mka(), n = 8)
  if b.n != 8 { return 71 }
  match b.p { A(v) => chk_a(v, 73, 74), B(v, w) => 72, _ => 75 }
}

## a field BEFORE and a field AFTER the enum field: a wrong width mis-aligns everything after it, and a
## wrong base mis-reads everything before it
lead_call := fn() -> u64 {
  l := Lead(lead = 4, p = mkb(), n = 9)
  if l.lead != 4 { return 81 }
  if l.n != 9 { return 82 }
  match l.p { A(v) => 83, B(v, w) => chk_b(v, w, 84, 85, 86, 87), _ => 88 }
}

## CONTROL — a PAYLOAD-FREE enum from the same shape is ONE word and already answered correctly on all
## three backends. It must keep doing so, and its emitted aarch64/riscv64 text is deliberately left
## byte-identical: the multi-word writers decline a one-word enum call exactly as they decline a
## one-word enum local.
holder_call := fn() -> u64 {
  h := Holder(t = green(), n = 7)
  if h.n != 7 { return 91 }
  match h.t { Red => 92, Green => 0, _ => 93 }
}

## CONTROL — the documented workaround: bind the call's result to a LOCAL, then build the struct from
## that enum PLACE (the #448 / PR #460 route). Correct on the parent and on this tree, on all three.
bound_local := fn() -> u64 {
  e := mkb()
  b := Boxed(p = e, n = 9)
  if b.n != 9 { return 101 }
  match b.p { A(v) => 102, B(v, w) => chk_b(v, w, 103, 104, 105, 106), _ => 107 }
}

## the same feed one level DOWN, inside a NESTED struct literal, where both writers recurse. Only the
## surrounding words are read back: `match o.inner.p` — a match over a NESTED enum place — is issue #447
## and is deliberately not measured here. A one-word store of the inner enum call mis-places `inner.n`
## and `tail` alike, which is what these two codes see.
##   111  the OUTER field after the nested struct is wrong
##   112  the INNER field after the enum field is wrong
nested_call := fn() -> u64 {
  o := Outer(inner = Boxed(p = mkb(), n = 9), tail = 3)
  if o.tail != 3 { return 111 }
  if o.inner.n != 9 { return 112 }
  0
}

main := fn() -> u64 {
  r1 := call_solo()
  if r1 != 0 { return r1 }
  r2 := call_b()
  if r2 != 0 { return r2 }
  r3 := call_a()
  if r3 != 0 { return r3 }
  r4 := lead_call()
  if r4 != 0 { return r4 }
  r5 := holder_call()
  if r5 != 0 { return r5 }
  r6 := bound_local()
  if r6 != 0 { return r6 }
  r7 := nested_call()
  if r7 != 0 { return r7 }
  42
}
