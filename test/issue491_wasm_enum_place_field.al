## issue #491 — on WASM, a struct field FED BY AN ENUM PLACE was stored ONE word wide, so the field
## AFTER it landed `enum_max_arity` words too early and read a wrong value WITH NO TRAP.
##
## An enum PLACE is a local or a param whose slot already holds the `{disc, payload…}` block: `e :=
## mkb()`, `e := Pay.B(5, 6)`, or an `e : Pay` parameter. `emit_wat_store_payload_at` is the flattened
## aggregate writer, and after PR #490 it knew a StructLit, an EnumLit, an ArrayLit and an
## enum-returning CALL. A `Var` was none of those, so the field got the place's BLOCK ADDRESS as its
## single word and the caller advanced the cumulative offset by 8 instead of `(1 + enum_max_arity) * 8`.
## Every reader still resolved `field_word_offset`, which is why the neighbour, not the enum field, is
## where the wrong number shows up. Measured on the parent WAT for `Lead(lead = 4, p = e, n = 9)`: the
## block reserves 40 bytes, `p` stores the pointer at +8, `n` stores 9 at +16, and `l.n`'s reader loads
## +32 — a word nothing ever wrote. The reservation was already the flattened `struct_words`, so the
## block had room; only the store was short.
##
## THREE distinct defects live at this one writer and this file is the third. #449 / PR #468 are the
## enum-field READ (`match s.p` is fail-loud on wasm, 134). #488 / PR #490 are the enum-returning CALL
## feed (silent, the field after read 0). This is the enum PLACE feed: also silent, also the field after,
## and PR #490's new arm matched `Expr::Call` only — deliberately, because a place has no call to make
## and needed its own materialisation. All three place spellings were measured broken and all three are
## covered below, because they resolve through different halves of `base_enum_type`: a local from a CALL
## init, a local from an ENUM-LITERAL init, and a PARAM annotation.
##
## Payload CONTENT is deliberately not read back on wasm: every spelling that reads a struct's enum
## field (`match l.p`, `use(l.p)`) is the #449 refusal and would trap this whole file at 134 and cost it
## every code below. The word-count and placement of the block are what this fixture measures, and the
## neighbour sentinels are chosen so a MISPLACED payload word is a different code from a missing one:
## the payloads are 5, 6 and 7, the discriminants 0 and 1, and the sentinels 3, 4, 9 and 10 — no value
## is shared between the two sets.
##
## Every observable carries its OWN exit code, so the number names the half that failed. "read 0" and
## "read some other wrong value" are deliberately different numbers — 0 is both this defect's answer
## and the commonest default, so aliasing them would hide which one happened. Per shape the five codes
## are: the field AFTER the enum field read 0 / read the NEXT scalar's sentinel (the store was short by
## exactly ONE word) / read a PAYLOAD word / read the DISCRIMINANT / read some THIRD value.
##   50 51 52 53 54          Boxed, place from a CALL init — the minimal shape
##   60 61 62 63 64 65       Lead, place from a CALL init (60 = the field BEFORE it, a mis-placed base)
##   70 71 72 73 74 75 76 77 Wide/B, call init — 76/77 are its SECOND trailing scalar (0, then other)
##   80 81 82 83 84 85 86 87 Wide/A, call init — the ONE-payload-word variant
##   90 91 92 93 94 95       Lead, place from an ENUM-LITERAL init
##   96 97 98 99 100 101 102 103   Wide/A, place from an ENUM-LITERAL init
##   104 105 106 107 108 109       Lead, an enum PARAM place
##   110 111 112 113 114 115 116 117  Wide/A, an enum PARAM place
##   118 / 119               a NESTED struct literal's outer tail / inner trailing scalar moved
##   120 121 122 123         the enum-LITERAL control moved — the shared reader/offset path broke
## A trap is not a code: wasm's `unreachable` is 134 and aarch64/riscv64's `brk`/`ebreak` is 133, both
## above every number above. All codes are < 126 so WASI `proc_exit` keeps them, and none of them is 42.
## A discriminant of 0 (variant `A`) is reported by the "read 0" code rather than the "read the
## discriminant" one, because those two are the same value and no fixture can separate them; the `B`
## shapes, whose discriminant is 1, are what make the discriminant class observable at all.
##
## `test/issue488_wasm_enum_call_field.al` is this fixture's model and NOT its duplicate: that file's
## feed is `p = mkb()` written INLINE in the constructor, the one shape PR #490 fixed and the one shape
## this defect is not. `test/issue462_enum_call_field.al` cannot host either measurement — its first
## observable is `match s.p` over a struct's enum field, so on wasm it refuses at 134 before reaching a
## single one of its codes, which is why #488 and #491 each needed their own file.
##
## Measured with the cross binutils under qemu on parent 2abfe57: wasm 50 and x86_64 42, aarch64 42,
## riscv64 42. This tree: 42 on all four. 50 is `boxed_place`, the FIRST observable; each shape was also
## isolated into its own `main` on that same parent, and every one of the nine place shapes answered
## with its OWN code — 50, 61, 71, 81, 91, 97, 105, 111, 119 — while `lit_control` answered 42 on all
## four backends on BOTH sides. All nine are the "read 0" code and none is the "short by one word" code,
## which is the measured mechanism and not a guess: for `Lead` the pointer store puts `p` at word 1 and
## `n` at word 2, while `l.n`'s reader resolves `field_word_offset` to word 4 — a word nothing wrote.
## The "read the NEXT scalar" codes therefore stay unreached on purpose; they name the other mechanism
## a short store could have had, and would fire if this were a partial-width copy instead of a pointer.

Pay := enum { A(u64), B(u64, u64) }

Boxed := struct { p : Pay, n : u64 }
Lead  := struct { lead : u64, p : Pay, n : u64 }
Wide  := struct { lead : u64, p : Pay, n1 : u64, n2 : u64 }
Outer := struct { inner : Boxed, tail : u64 }

mkb := fn() -> Pay { Pay.B(5, 6) }
mka := fn() -> Pay { Pay.A(7) }

## Name the wrong number a trailing scalar read. `v` is what it read, `want` what it owed, `nxt` the
## NEXT trailing scalar's sentinel (reading that one means the store was short by exactly one word).
## The payload words 5, 6, 7 and the discriminants 0, 1 are all distinct from every sentinel, so each
## branch below names one mechanism and no two mechanisms share a code.
chk_after := fn(v : u64, want : u64, nxt : u64, zero : u64, shift : u64, payload : u64, disc : u64, other : u64) -> u64 {
  if v == want { return 0 }
  if v == 0 { return zero }
  if v == nxt { return shift }
  if v == 5 { return payload }
  if v == 6 { return payload }
  if v == 7 { return payload }
  if v == 1 { return disc }
  other
}

## the enum field FIRST, one scalar after it — the minimal shape that can see a short store
boxed_place := fn() -> u64 {
  e := mkb()
  b := Boxed(p = e, n = 9)
  chk_after(b.n, 9, 9, 50, 51, 52, 53, 54)
}

## the issue's own reproducer: a scalar BEFORE and a scalar AFTER, so a wrong width moves everything
## after the enum field and a wrong base mis-reads everything before it
lead_place := fn() -> u64 {
  e := mkb()
  l := Lead(lead = 4, p = e, n = 9)
  if l.lead != 4 { return 60 }
  chk_after(l.n, 9, 9, 61, 62, 63, 64, 65)
}

## TWO trailing scalars. This is the shape that tells "short by exactly one word" from "short by two or
## more": a two-word store puts `n1` where `n2`'s reader looks, so `n1` reads 10 and not 0.
wide_place_b := fn() -> u64 {
  e := mkb()
  w := Wide(lead = 4, p = e, n1 = 9, n2 = 10)
  if w.lead != 4 { return 70 }
  r := chk_after(w.n1, 9, 10, 71, 72, 73, 74, 75)
  if r != 0 { return r }
  if w.n2 == 10 { return 0 }
  if w.n2 == 0 { return 76 }
  77
}

## the OTHER variant of the same enum, with ONE payload word. `Pay`'s field is `1 + enum_max_arity` = 3
## words whichever variant fills it, so a store sized by the HELD VARIANT's arity would write two words
## here and shift the tail — a one-word variant must not pass by coincidence.
wide_place_a := fn() -> u64 {
  e := mka()
  w := Wide(lead = 4, p = e, n1 = 9, n2 = 10)
  if w.lead != 4 { return 80 }
  r := chk_after(w.n1, 9, 10, 81, 82, 83, 84, 85)
  if r != 0 { return r }
  if w.n2 == 10 { return 0 }
  if w.n2 == 0 { return 86 }
  87
}

## the SECOND place spelling: a local bound to an enum LITERAL, not to a call. `base_enum_type` reaches
## it through `local_enum_type`'s EnumLit branch instead of its `callee_ret_enum` branch, so a fix that
## covered only the call-initialised local would leave this one short.
lead_place_lit := fn() -> u64 {
  e := Pay.B(5, 6)
  l := Lead(lead = 4, p = e, n = 9)
  if l.lead != 4 { return 90 }
  chk_after(l.n, 9, 9, 91, 92, 93, 94, 95)
}

wide_place_lit_a := fn() -> u64 {
  e := Pay.A(7)
  w := Wide(lead = 4, p = e, n1 = 9, n2 = 10)
  if w.lead != 4 { return 96 }
  r := chk_after(w.n1, 9, 10, 97, 98, 99, 100, 101)
  if r != 0 { return r }
  if w.n2 == 10 { return 0 }
  if w.n2 == 0 { return 102 }
  103
}

## the THIRD place spelling: an enum PARAM, which resolves through `param_enum_type` — a different half
## of `base_enum_type` again, and the one that has no `:=` statement to walk at all.
lead_param := fn(e : Pay) -> u64 {
  l := Lead(lead = 4, p = e, n = 9)
  if l.lead != 4 { return 104 }
  chk_after(l.n, 9, 9, 105, 106, 107, 108, 109)
}

wide_param_a := fn(e : Pay) -> u64 {
  w := Wide(lead = 4, p = e, n1 = 9, n2 = 10)
  if w.lead != 4 { return 110 }
  r := chk_after(w.n1, 9, 10, 111, 112, 113, 114, 115)
  if r != 0 { return r }
  if w.n2 == 10 { return 0 }
  if w.n2 == 0 { return 116 }
  117
}

## the same feed one level DOWN, inside a NESTED struct literal, where the flattened writer recurses.
## A short inner store moves the inner trailing scalar AND the outer field that follows the whole
## nested struct.
nested_place := fn() -> u64 {
  e := mkb()
  o := Outer(inner = Boxed(p = e, n = 9), tail = 3)
  if o.tail != 3 { return 118 }
  if o.inner.n != 9 { return 119 }
  0
}

## CONTROL — the enum LITERAL written INLINE in the constructor. Same structs, same offsets, same
## readers, and the arm right above the new one in the writer. Correct on the parent and on this tree,
## on every backend: that is what proves this defect is the STORE's width for a PLACE feed and neither
## the field read (#449) nor a broken reader.
lit_control := fn() -> u64 {
  l := Lead(lead = 4, p = Pay.B(5, 6), n = 9)
  if l.lead != 4 { return 120 }
  if l.n != 9 { return 121 }
  w := Wide(lead = 4, p = Pay.A(7), n1 = 9, n2 = 10)
  if w.n1 != 9 { return 122 }
  if w.n2 != 10 { return 123 }
  0
}

main := fn() -> u64 {
  r1 := boxed_place()
  if r1 != 0 { return r1 }
  r2 := lead_place()
  if r2 != 0 { return r2 }
  r3 := wide_place_b()
  if r3 != 0 { return r3 }
  r4 := wide_place_a()
  if r4 != 0 { return r4 }
  r5 := lead_place_lit()
  if r5 != 0 { return r5 }
  r6 := wide_place_lit_a()
  if r6 != 0 { return r6 }
  r7 := lead_param(mkb())
  if r7 != 0 { return r7 }
  r8 := wide_param_a(mka())
  if r8 != 0 { return r8 }
  r9 := nested_place()
  if r9 != 0 { return r9 }
  r10 := lit_control()
  if r10 != 0 { return r10 }
  42
}
