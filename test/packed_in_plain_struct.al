## §8 a @packed struct used as a FIELD of a NON-packed struct (DEFERRED, spec Types §8) — the build must
## FAIL LOUD. The outer struct lays its fields out with the WORD model (each field at `8 * word index`),
## but the nested literal `Big(z = 1, p = Pk(…))` routes the inner value through the @packed byte-precise
## store. Write and read then disagree: `g.p.b` read the word at `index(p) + index(b)` while `b` lives at
## BYTE 1 of the word at `index(p)` — a SILENT WRONG VALUE (0), and `g.p.a` read the whole first word
## (all three packed fields OR-ed together) which an exit-code check mod 256 could even mistake for right.
## The MIRROR direction — a plain struct nested INSIDE a @packed struct — is supported (packed_agg_read /
## packed_nested_struct) and unaffected; only packed-inside-plain is rejected.
## build_reject asserts the non-zero build rc.
Pk  := @packed struct { a : u8, b : u16, c : u32 }
Big := struct { z : u64, p : Pk }

main := fn() -> u64 {
  g := Big(z = 1, p = Pk(a = 10, b = 20, c = 12))
  if g.z != 1 { return 4 }
  u64(g.p.b)
}
