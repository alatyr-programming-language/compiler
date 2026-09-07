## issue #497 — a struct field whose declared type is a RAW UNION was stored with the WRONG WORD COUNT
## on wasm, aarch64 and riscv64, so the scalar field written AFTER it landed at the wrong offset and
## read a wrong value WITH NO TRAP.
##
## `field_words` reserves `union_words` for a union-typed field: the members OVERLAP AT OFFSET 0 and
## there is NO discriminant word (spec Types §6.3). That is a DIFFERENT sizer from an enum's
## `1 + enum_max_arity`, and it is the whole defect: a `union { m(T), … }` parses into the SAME kind-3
## decl and the same `EnumLit` construction an `enum` does, so `enum_decl_of` — and therefore every
## `param_enum_type` / `local_enum_type` / `callee_ret_enum*` resolver and every enum-shaped store arm
## on those three backends — answers YES for a union. Each of them then either wrote `1 + max_arity`
## words with a DISCRIMINANT at word 0 (one word too wide AND one word out of place) or fell to a
## scalar fallback that wrote ONE pointer/discriminant word where `union_words` were due. Every reader
## still resolved `field_word_offset`, which is why the wrong number appears in the NEIGHBOUR and never
## in the union field itself.
##
## Measured on parent 240b8ff over `U := union { a(u64), b(u64) }` (one word) and
## `W := union { a(u64), p(Pair) }` (two words), for `Lead(lead = 4, p = <feed>, n = 9, big = …)`:
##
##   feed                         x86_64  wasm  aarch64  riscv64
##   the union LITERAL              42     63      63       63       (one-word member)
##   a union-returning CALL         42     63      63       63
##   a union PLACE (lit init)       42   * 42      63       63
##   a union PLACE (call init)      42   * 42      63       63
##   a union PARAM                  42   * 42      63       63
##   every one of those, WIDE       42     64/61   61       61
##
## The `* 42`s are the reason this file exists. They are a COINCIDENCE, not correctness: a ONE-WORD
## union field and a ONE-WORD pointer store agree by construction, and the same five feeds over a
## union with a WIDER member answer 61 or 64 on every one of the three backends. So EVERY shape below
## is measured at BOTH widths, and the wide `W` is measured with the WIDE member held (`W.p(Pair)`)
## AND with the NARROW one held (`W.a`) — a store sized by the HELD member's arity, rather than by
## `union_words`, would pass the second and move the tail on the first.
##
## `big` is there to keep the owning struct off the all-scalar positional path, which is what routes it
## through the flattened aggregate writer at all — the writer this defect lives in.
##
## Payload CONTENT is deliberately NOT read back here. Reading a union member (`u.m`, `s.p.m`) is a
## separate and already-LOUD surface on these three backends — measured 134 on wasm and 133 on
## aarch64/riscv64, the #449 class — so a single `l.p.a` would trap this whole file above every code
## below and cost it every measurement. `test/union_struct_field.al` and `test/union_struct_member.al`
## already own the member-content assertion on x86_64, where the read works. The word COUNT and the
## PLACEMENT of the field are what this fixture measures, through the neighbour, which is where the
## corruption was. A union-returning call whose held member is a STRUCT is loud on aarch64 and riscv64
## — 133 on the parent AND on this tree, because the register return convention cannot deliver a struct
## payload — so the two CALL shapes below hold a scalar member on purpose. (On wasm that same shape was
## a silent 64 on the parent and is 42 on this tree; it is not below because the file must stay under
## every backend's loud floor to keep its codes.)
##
## Every observable carries its OWN code, so the number names the shape AND the mechanism. Per shape
## the seven codes are, in order:
##   +0 the field BEFORE the union field (`lead`) read wrong — the owner's base was mis-placed
##   +1 the field AFTER read 0 — nothing wrote its slot
##   +2 the field AFTER read the NEXT thing in the layout (21) — the store was SHORT by exactly one word
##   +3 the field AFTER read an aggregate PAYLOAD word (5, 6, 7, 8, 11, 12, 13) — member data landed in it
##   +4 the field AFTER read a DISCRIMINANT (1) — an enum tag leaked into an UNTAGGED union field
##   +5 the field AFTER read a LATER word of `big` (22, 23) — the store ran LONG past the field
##   +6 the field AFTER read some THIRD value
## The blocks are:
##   43-49    one-word union, the LITERAL feed
##   50-56    one-word union, a union-returning CALL
##   57-63    one-word union, a PLACE bound to a union literal
##   64-70    one-word union, a PLACE bound to a union-returning call
##   71-77    one-word union, a union PARAM
##   78-84    two-word union, the LITERAL feed, WIDE member held
##   85-91    two-word union, the LITERAL feed, NARROW member held
##   92-98    two-word union, a union-returning CALL
##   99-105   two-word union, a PLACE bound to a union literal
##   106-112  two-word union, a union PARAM
##   113-122  two-word union, TWO trailing scalars — 113-119 for `n1`, then 120 (`n2` read 0),
##            121 (`n2` read a `big` word) and 122 (`n2` read something else)
##   123/124/125  the ENUM controls (literal / call / place) — one code each, because a control's job
##            is to stay put and the number only has to say WHICH control moved
## A discriminant of 0 is reported by the "read 0" code rather than the discriminant one: those two are
## the same value and no fixture can separate them, which is why the `b`/`B` shapes (discriminant 1)
## are what make the tag class observable at all. A trap is not a code: wasm's `unreachable` is 134 and
## aarch64/riscv64's `brk`/`ebreak` is 133, both above every number here. Every code is < 126 so WASI
## `proc_exit` keeps it, and none of them is 42.

Pair := struct { x : u64, y : u64 }

## ONE word — the width at which a pointer store passes by coincidence.
U := union { a(u64), b(u64) }
## TWO words — the width at which no coincidence survives. `union_words` is 2 whichever member is held.
W := union { a(u64), p(Pair) }
Pay := enum { A(u64), B(u64, u64) }

Big := struct { z0 : u64, z1 : u64, z2 : u64 }

Lead  := struct { lead : u64, p : U, n : u64, big : Big }
LeadW := struct { lead : u64, q : W, n : u64, big : Big }
Two   := struct { lead : u64, q : W, n1 : u64, n2 : u64, big : Big }
LeadE := struct { lead : u64, e : Pay, n : u64, big : Big }

mku := fn() -> U { U.a(5) }
mkw := fn() -> W { W.a(6) }
mkb := fn() -> Pay { Pay.B(11, 12) }

## Name the wrong number a trailing scalar read. `v` is already known not to be the due value; `nxt` is
## the next thing the layout puts after it, so reading THAT means the store was short by exactly one
## word. The payload words 5, 6, 7, 8, 11, 12, 13 and the discriminants 0, 1 share no value with any
## sentinel (4, 9, 10, 21, 22, 23), so each branch names one mechanism and no two mechanisms collide.
clsf := fn(v : u64, nxt : u64, zero : u64, shift : u64, payload : u64, disc : u64, big : u64, other : u64) -> u64 {
  if v == 0 { return zero }
  if v == nxt { return shift }
  if v == 5 { return payload }
  if v == 6 { return payload }
  if v == 7 { return payload }
  if v == 8 { return payload }
  if v == 11 { return payload }
  if v == 12 { return payload }
  if v == 13 { return payload }
  if v == 1 { return disc }
  if v == 21 { return big }
  if v == 22 { return big }
  if v == 23 { return big }
  other
}

## ---- one word wide: `union_words` == 1, where a single pointer/discriminant store coincides ----

## the union LITERAL written INLINE in the constructor. The enum-shaped arm writes a discriminant at
## word 0 and reports `1 + enum_max_arity` = 2 for a field that reserves 1.
lit_one := fn() -> u64 {
  l := Lead(lead = 4, p = U.a(5), n = 9, big = Big(z0 = 21, z1 = 22, z2 = 23))
  if l.lead != 4 { return 43 }
  if l.n == 9 { return 0 }
  clsf(l.n, 21, 44, 45, 46, 47, 48, 49)
}

## a union-returning CALL. §8 delivers it the way it delivers an enum — a `{disc, payload…}` block, in
## the return registers on the native backends and by base address on wasm.
call_one := fn() -> u64 {
  l := Lead(lead = 4, p = mku(), n = 9, big = Big(z0 = 21, z1 = 22, z2 = 23))
  if l.lead != 4 { return 50 }
  if l.n == 9 { return 0 }
  clsf(l.n, 21, 51, 52, 53, 54, 55, 56)
}

## a union PLACE bound to a union LITERAL — resolved through the `EnumLit`-init half of the local
## resolver, a different half from the call-init one below.
place_lit_one := fn() -> u64 {
  u := U.a(5)
  l := Lead(lead = 4, p = u, n = 9, big = Big(z0 = 21, z1 = 22, z2 = 23))
  if l.lead != 4 { return 57 }
  if l.n == 9 { return 0 }
  clsf(l.n, 21, 58, 59, 60, 61, 62, 63)
}

## a union PLACE bound to a union-returning CALL — the other half of the local resolver.
place_call_one := fn() -> u64 {
  u := mku()
  l := Lead(lead = 4, p = u, n = 9, big = Big(z0 = 21, z1 = 22, z2 = 23))
  if l.lead != 4 { return 64 }
  if l.n == 9 { return 0 }
  clsf(l.n, 21, 65, 66, 67, 68, 69, 70)
}

## a union PARAM place, which has no `:=` statement to walk at all and resolves through the param
## annotation. On the native backends its slot holds the caller's block POINTER, not the block.
param_one := fn(u : U) -> u64 {
  l := Lead(lead = 4, p = u, n = 9, big = Big(z0 = 21, z1 = 22, z2 = 23))
  if l.lead != 4 { return 71 }
  if l.n == 9 { return 0 }
  clsf(l.n, 21, 72, 73, 74, 75, 76, 77)
}

## ---- two words wide: `union_words` == 2, where every coincidence above dies ----

## the WIDE member held: two payload words at offset 0, still no discriminant.
lit_wide_p := fn() -> u64 {
  l := LeadW(lead = 4, q = W.p(Pair(x = 7, y = 8)), n = 9, big = Big(z0 = 21, z1 = 22, z2 = 23))
  if l.lead != 4 { return 78 }
  if l.n == 9 { return 0 }
  clsf(l.n, 21, 79, 80, 81, 82, 83, 84)
}

## the NARROW member of the SAME two-word union. The field is `union_words` = 2 words whichever member
## fills it, so a store sized by the HELD member's arity would write one word here and move the tail.
lit_wide_a := fn() -> u64 {
  l := LeadW(lead = 4, q = W.a(6), n = 9, big = Big(z0 = 21, z1 = 22, z2 = 23))
  if l.lead != 4 { return 85 }
  if l.n == 9 { return 0 }
  clsf(l.n, 21, 86, 87, 88, 89, 90, 91)
}

## a CALL returning the two-word union. It holds the scalar member on purpose: a struct-payload union
## return is a separate, already-loud refusal on aarch64 and riscv64.
call_wide := fn() -> u64 {
  l := LeadW(lead = 4, q = mkw(), n = 9, big = Big(z0 = 21, z1 = 22, z2 = 23))
  if l.lead != 4 { return 92 }
  if l.n == 9 { return 0 }
  clsf(l.n, 21, 93, 94, 95, 96, 97, 98)
}

## a two-word union PLACE bound to a literal that holds the WIDE member.
place_wide := fn() -> u64 {
  u := W.p(Pair(x = 7, y = 8))
  l := LeadW(lead = 4, q = u, n = 9, big = Big(z0 = 21, z1 = 22, z2 = 23))
  if l.lead != 4 { return 99 }
  if l.n == 9 { return 0 }
  clsf(l.n, 21, 100, 101, 102, 103, 104, 105)
}

## a two-word union PARAM holding the WIDE member.
param_wide := fn(u : W) -> u64 {
  l := LeadW(lead = 4, q = u, n = 9, big = Big(z0 = 21, z1 = 22, z2 = 23))
  if l.lead != 4 { return 106 }
  if l.n == 9 { return 0 }
  clsf(l.n, 21, 107, 108, 109, 110, 111, 112)
}

## TWO trailing scalars. This is the shape that tells "short by exactly one word" from "short by two or
## more": a one-word store puts `n1` where `n2`'s reader looks, so `n1` reads 10 and not 0.
two_trailing := fn() -> u64 {
  u := mkw()
  t := Two(lead = 4, q = u, n1 = 9, n2 = 10, big = Big(z0 = 21, z1 = 22, z2 = 23))
  if t.lead != 4 { return 113 }
  if t.n1 != 9 {
    return clsf(t.n1, 10, 114, 115, 116, 117, 118, 119)
  }
  if t.n2 == 10 { return 0 }
  if t.n2 == 0 { return 120 }
  if t.n2 == 21 { return 121 }
  if t.n2 == 22 { return 121 }
  if t.n2 == 23 { return 121 }
  122
}

## ---- the ENUM controls: the same three feeds over a real `enum`, which #462 / #488 / #491 fixed ----
## They must be correct on the parent AND on this tree, on every backend. That is what proves this
## change touched the UNION sizer and left the enum one where it was.
enum_controls := fn() -> u64 {
  l := LeadE(lead = 4, e = Pay.B(11, 12), n = 9, big = Big(z0 = 21, z1 = 22, z2 = 23))
  if l.lead != 4 { return 123 }
  if l.n != 9 { return 123 }
  c := LeadE(lead = 4, e = mkb(), n = 9, big = Big(z0 = 21, z1 = 22, z2 = 23))
  if c.lead != 4 { return 124 }
  if c.n != 9 { return 124 }
  e := mkb()
  p := LeadE(lead = 4, e = e, n = 9, big = Big(z0 = 21, z1 = 22, z2 = 23))
  if p.lead != 4 { return 125 }
  if p.n != 9 { return 125 }
  0
}

main := fn() -> u64 {
  r1 := lit_one()
  if r1 != 0 { return r1 }
  r2 := call_one()
  if r2 != 0 { return r2 }
  r3 := place_lit_one()
  if r3 != 0 { return r3 }
  r4 := place_call_one()
  if r4 != 0 { return r4 }
  r5 := param_one(U.a(5))
  if r5 != 0 { return r5 }
  r6 := lit_wide_p()
  if r6 != 0 { return r6 }
  r7 := lit_wide_a()
  if r7 != 0 { return r7 }
  r8 := call_wide()
  if r8 != 0 { return r8 }
  r9 := place_wide()
  if r9 != 0 { return r9 }
  r10 := param_wide(W.p(Pair(x = 7, y = 8)))
  if r10 != 0 { return r10 }
  r11 := two_trailing()
  if r11 != 0 { return r11 }
  r12 := enum_controls()
  if r12 != 0 { return r12 }
  42
}
