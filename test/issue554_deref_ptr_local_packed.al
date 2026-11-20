## Issue #554 / Memory §4.3, Types §8 — `deref(ptr(l)).f` on a `@packed` struct LOCAL reads the field at
## its packed byte offset with its own width and sign, the same as `l.f`. Decided at the pinned revision
## 1.10.0 (tag v1.10.0, commit 624f476).
##
## `P` packs to `a`@0, `b`@1, `c`@5, 7 bytes. The first fix for this root read fields as 8-byte words at
## index × 8: `c` came from byte 16, past the struct, and answered 0 where 51 is due; `b` read a word
## that also held `a` and `c`. `Q` adds signed fields, so a load that zero-extends a negative value
## fails here. Each case returns `10 * case + 1` when wrong; 99 only when all are right. Case 4 is the
## direct `l.f` control.
##
## The twins trap at their field-access stub (#1187), listed in scripts/known-deviations.tsv.
P := @packed struct { a : u8, b : u32, c : u16 }
Q := @packed struct { p : i8, q : i16, r : i32 }

main := fn() -> u64 {
  l := P(a = 3, b = 50, c = 51)
  ## 1 — each field of P at its packed offset.
  if deref(ptr(l)).a != 3 { return 11 }
  if deref(ptr(l)).b != 50 { return 12 }
  if deref(ptr(l)).c != 51 { return 13 }
  ## 2 — signed packed fields, each sign-extended.
  m := Q(p = -5, q = -300, r = -100000)
  if deref(ptr(m)).p != -5 { return 21 }
  if deref(ptr(m)).q != -300 { return 22 }
  if deref(ptr(m)).r != -100000 { return 23 }
  ## 3 — widened and summed: -5 - 300 - 100000.
  s : i64 = i64(deref(ptr(m)).p) + i64(deref(ptr(m)).q) + i64(deref(ptr(m)).r)
  if s != -100305 { return 31 }
  ## 4 — control: the direct read.
  if l.c != 51 { return 41 }
  99
}
## expect: run 99
