## Issue #554 / Memory §4.3 — `deref(ptr(l)).f` on a struct LOCAL whose fields are NARROW is the read
## `l.f`: the field's own bytes, sign- or zero-extended by its own type. Decided at the pinned revision
## 1.10.0 (tag v1.10.0, commit 624f476): `deref(p)` "yields the place it denotes", and the place of
## `ptr(l)` is `l`.
##
## A struct with a sub-word scalar field is stored in the standard byte layout (Types §6.1): `S` below
## is `x`@0, `y`@2, `z`@4, `w`@8, 12 bytes. The first fix for this root read every field as an 8-byte word
## at index × 8, which is right only when every field is a full word. On `S` it read `y` from byte 8,
## which is `w` (`u64(y + 1050)` answered 226 where 50 is due), `z` from byte 16 (past the struct) and
## `w` from byte 24 (the saved frame pointer); `x` came back as the whole first word and failed the i8
## range check. The read now asks the layout of the struct, as the `deref(p).f` arm does.
##
## Each case returns `10 * case + 1` when its read is wrong; 99 only when all are right. Cases 1–4 read
## each field of one local, so a wrong offset or a missing sign extension shows up in its own case.
## Case 5 sums them as i64. Case 6 uses a different field order and an unsigned 16-bit field, so
## zero extension is checked too. Case 7 reads a payload-less enum field of a word-layout struct, which
## is its one-word discriminant. Case 8 is the direct `l.f` control.
##
## The twins trap at their field-access stub (#1187), listed in scripts/known-deviations.tsv.
S := struct { x : i8, y : i16, z : i32, w : u8 }
U := struct { a : u8, b : u16, c : i8, d : u32 }
C := enum { R, G, B }
H := struct { k : u64, t : C, z : u64 }

main := fn() -> u64 {
  l := S(x = -3, y = -1000, z = -70000, w = 200)
  ## 1 — the i8 at byte 0.
  if deref(ptr(l)).x != -3 { return 11 }
  ## 2 — the i16 at byte 2.
  if deref(ptr(l)).y != -1000 { return 21 }
  ## 3 — the i32 at byte 4.
  if deref(ptr(l)).z != -70000 { return 31 }
  ## 4 — the u8 at byte 8.
  if deref(ptr(l)).w != 200 { return 41 }
  ## 5 — all four widened to i64: -3 - 1000 - 70000 + 200.
  s : i64 = i64(deref(ptr(l)).x) + i64(deref(ptr(l)).y) + i64(deref(ptr(l)).z) + i64(deref(ptr(l)).w)
  if s != -70803 { return 51 }
  ## 6 — another order, zero extension of u8/u16/u32 beside a negative i8.
  u := U(a = 250, b = 65000, c = -128, d = 4000000000)
  if deref(ptr(u)).a != 250 { return 61 }
  if deref(ptr(u)).b != 65000 { return 62 }
  if deref(ptr(u)).c != -128 { return 63 }
  if deref(ptr(u)).d != 4000000000 { return 64 }
  ## 7 — a payload-less enum field: one word, its discriminant.
  h := H(k = 7, t = C.B, z = 9)
  if deref(ptr(h)).t != C.B { return 71 }
  if deref(ptr(h)).z != 9 { return 72 }
  ## 8 — control: the direct read of the same local.
  if l.y != -1000 { return 81 }
  99
}
## expect: run 99
