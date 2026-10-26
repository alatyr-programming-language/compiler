## Expected exit: 20 — §8 a @packed struct used as a FIELD of a NON-packed struct (spec Types §8) RUNS
## and `g.p.b` reads 20, byte-precise. It used to be DEFERRED and refused, because the outer struct laid
## its fields out with the WORD model (each field at `8 * word index`) while the nested literal
## `Big(z = 1, p = Pk(…))` routed the inner value through the @packed byte-precise store: write and read
## disagreed, `g.p.b` read the word at `index(p) + index(b)` while `b` lives at BYTE 1 of the word at
## `index(p)` — a SILENT WRONG VALUE (0), and `g.p.a` read the whole first word (all three packed fields
## OR-ed together) which an exit-code check mod 256 could even mistake for right. Refusing was the
## honest answer then. It is not now: the shared IR's x86 selector keeps the byte layout consistent across
## write and read and answers 20, which is what aarch64, riscv64 and WAT already answered — measured on
## native x86_64 through the DEFAULT surface after the slice-9 flip (`docs/ir.md` §7.4, #980). #1022:
## a refusal the other three backends do not share is not a requirement.
## The MIRROR direction — a plain struct nested INSIDE a @packed struct — is supported (packed_agg_read /
## packed_nested_struct) and unaffected on both surfaces.
Pk  := @packed struct { a : u8, b : u16, c : u32 }
Big := struct { z : u64, p : Pk }

main := fn() -> u64 {
  g := Big(z = 1, p = Pk(a = 10, b = 20, c = 12))
  if g.z != 1 { return 4 }
  u64(g.p.b)
}
