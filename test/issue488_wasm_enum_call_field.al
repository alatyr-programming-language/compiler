## issue #488 — on WASM, a struct field FED BY AN ENUM-RETURNING CALL was stored ONE word wide, so the
## field AFTER it landed `enum_max_arity` words too early and read a wrong value WITH NO TRAP.
##
## `emit_wat_store_payload_at` is the flattened aggregate writer: it knows a StructLit, an EnumLit and
## an ArrayLit, and everything else falls to a scalar `(i64.store … <expr>)` that reports ONE word. An
## enum-returning CALL is none of the three, and on WASM such a call yields the i64 BASE ADDRESS of a
## freshly bump-allocated `{disc, payload…}` block — so the field got that POINTER as its single word
## and the caller advanced the cumulative offset by 8 instead of `(1 + enum_max_arity) * 8`. Every
## reader still resolved `field_word_offset`, which is why the neighbour, not the enum field, is where
## the wrong number shows up. The reservation was already the flattened `struct_words`, so the block
## had room; only the store was short.
##
## NOT #449. #449 / PR #468 are the wasm enum-field *READ*: `match s.p` over a struct's enum field is
## fail-loud there (134). This defect never reads the enum field at all — every observable below is a
## SCALAR neighbour — so it produced a clean exit with a wrong answer. The enum-LITERAL control at the
## bottom is what separates the two mechanisms: it walks the same constructor, the same offsets and the
## same readers and answers 42 on the parent. A read defect would take it down too.
##
## Payload CONTENT is deliberately not read back on wasm: every spelling that reads a struct's enum
## field (`match l.p`, `use(l.p)`) is the #449 refusal and would trap this whole file at 134 and cost it
## every code below. The word-count and placement of the block are what this fixture measures, and the
## neighbour sentinels are chosen so a MISPLACED payload word is a different code from a missing one:
## the payloads are 5, 6 and 7 and the discriminants 0 and 1, none of which is a neighbour's value.
##
## Every observable carries its OWN exit code, so the number names the half that failed. "read 0" and
## "read some other wrong value" are deliberately different numbers — 0 is both this defect's answer
## and the commonest default, so aliasing them would hide which one happened:
##   50 / 61 / 71 / 81      the field AFTER the enum field read 0 — nothing landed at its own offset
##   51 / 62 / 72 / 82      it read the NEXT scalar's sentinel — the store was short by exactly ONE word
##   52 / 63 / 73 / 83      it read a PAYLOAD word — the block was written on top of it
##   53 / 64 / 74 / 84      it read the DISCRIMINANT — the whole block landed one field early
##   54 / 65 / 75 / 85      it read some THIRD wrong value
##   60 / 70 / 80           the field BEFORE the enum field is wrong — a mis-placed base
##   76 / 77 / 86 / 87      the SECOND trailing scalar is wrong (0, then any other value)
##   100 / 101              a NESTED struct literal's outer / inner field after the enum call moved
##   110 / 111 / 112 / 113  the enum-LITERAL control moved — the shared reader/offset path broke
## A trap is not a code: wasm's `unreachable` is 134 and aarch64/riscv64's `brk`/`ebreak` is 133, both
## above every number above. All codes are < 126 so WASI `proc_exit` keeps them.
##
## `test/issue462_enum_call_field.al` is this fixture's model and NOT its duplicate. That file's first
## observable is `match s.p` over a struct's enum field, so on wasm it refuses at 134 before reaching a
## single one of its codes — which is exactly why the wasm half of that shape class survived PR #487 and
## needed its own file. This one reuses that file's code SCHEME (one number per observable, "read 0"
## kept apart from "read some other wrong value", an enum-literal control that pins the expected answer
## without trusting any one backend) over the observables wasm can actually reach.
##
## Measured with the cross binutils under qemu on parent aa737b1 (PR #487 already merged, so the other
## three backends are green there): wasm 50 — the field after the enum field read 0 — and x86_64 42,
## aarch64 42, riscv64 42. This tree: 42 / 42 / 42 / 42. #462's own two fixtures are unmoved by this
## change: field 42 / 42 / 42 / 134 and elem 42 / 42 / 133 / 134 on both sides, because the 134 there is
## the #449 READ refusal and this change only widens a STORE.

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
boxed_call := fn() -> u64 {
  b := Boxed(p = mkb(), n = 9)
  chk_after(b.n, 9, 9, 50, 51, 52, 53, 54)
}

## a scalar BEFORE and a scalar AFTER: a wrong width moves everything after the enum field, a wrong
## base mis-reads everything before it
lead_call := fn() -> u64 {
  l := Lead(lead = 4, p = mkb(), n = 9)
  if l.lead != 4 { return 60 }
  chk_after(l.n, 9, 9, 61, 62, 63, 64, 65)
}

## TWO trailing scalars. This is the shape that tells "short by exactly one word" from "short by two or
## more": a two-word store puts `n1` where `n2`'s reader looks, so `n1` reads 10 and not 0.
wide_call_b := fn() -> u64 {
  w := Wide(lead = 4, p = mkb(), n1 = 9, n2 = 10)
  if w.lead != 4 { return 70 }
  r := chk_after(w.n1, 9, 10, 71, 72, 73, 74, 75)
  if r != 0 { return r }
  if w.n2 == 10 { return 0 }
  if w.n2 == 0 { return 76 }
  77
}

## the OTHER variant of the same enum, with ONE payload word. `Pay`'s field is `1 + enum_max_arity` = 3
## words whichever variant fills it, so a store sized by the CALLED VARIANT's arity would write two
## words here and shift the tail — a one-word variant must not pass by coincidence.
wide_call_a := fn() -> u64 {
  w := Wide(lead = 4, p = mka(), n1 = 9, n2 = 10)
  if w.lead != 4 { return 80 }
  r := chk_after(w.n1, 9, 10, 81, 82, 83, 84, 85)
  if r != 0 { return r }
  if w.n2 == 10 { return 0 }
  if w.n2 == 0 { return 86 }
  87
}

## the same feed one level DOWN, inside a NESTED struct literal, where the flattened writer recurses.
## A short inner store moves the inner trailing scalar AND the outer field that follows the whole
## nested struct.
nested_call := fn() -> u64 {
  o := Outer(inner = Boxed(p = mkb(), n = 9), tail = 3)
  if o.tail != 3 { return 100 }
  if o.inner.n != 9 { return 101 }
  0
}

## CONTROL — the enum LITERAL feed. Same structs, same offsets, same readers, and the arm right above
## the new one in the writer. Correct on the parent and on this tree, on every backend: that is what
## proves this defect is the STORE's width and not the field read (#449).
lit_control := fn() -> u64 {
  l := Lead(lead = 4, p = Pay.B(5, 6), n = 9)
  if l.lead != 4 { return 110 }
  if l.n != 9 { return 111 }
  w := Wide(lead = 4, p = Pay.A(7), n1 = 9, n2 = 10)
  if w.n1 != 9 { return 112 }
  if w.n2 != 10 { return 113 }
  0
}

main := fn() -> u64 {
  r1 := boxed_call()
  if r1 != 0 { return r1 }
  r2 := lead_call()
  if r2 != 0 { return r2 }
  r3 := wide_call_b()
  if r3 != 0 { return r3 }
  r4 := wide_call_a()
  if r4 != 0 { return r4 }
  r5 := nested_call()
  if r5 != 0 { return r5 }
  r6 := lit_control()
  if r6 != 0 { return r6 }
  42
}
