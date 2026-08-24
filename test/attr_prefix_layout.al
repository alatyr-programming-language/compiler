## e2e — a LAYOUT attribute written in DECLARATION-PREFIX position means the same thing as the
## value-position spelling. Declarations §2.3: "a declaration MAY carry … `@`-attributes … always in
## prefix position (the attribute precedes what it modifies)"; Grammar §3.2 spells it
## `declaration ::= { modifier } binding` with `modifier ::= "pub" | "mut" | "comptime" | attribute`.
##
## Before this the prefix spelling was ACCEPTED and the declared layout was thrown away without a
## word: `@packed` newline `Pk := struct { a : u8, b : u16, c : u32 }` laid out 24 bytes where the
## value-position `Pk := @packed struct { … }` lays out 7. A declared layout silently replaced by a
## different one is the forbidden failure, so both spellings are pinned here — and against the
## UNATTRIBUTED layout, so the test cannot pass by both being wrong the same way.
Rhs := @packed struct { a : u8, b : u16, c : u32 }
@packed
Pfx := struct { a : u8, b : u16, c : u32 }
@packed Same := struct { a : u8, b : u16, c : u32 }
@packed mut AfterAttr := struct { a : u8, b : u16, c : u32 }
Plain := struct { a : u8, b : u16, c : u32 }

## `@align(N)` on the declaration, both spellings — the struct's own alignment lever (Types §8).
## The body also asserts that the un-attributed layout is untouched, and that the packed layout is REAL
## rather than just a smaller reported size — the fields still round-trip through it.
## (Those two notes live in the HEADER, not in the body: `fmt` cannot retain an in-body comment,
## and `fmt_test` asserts comment fidelity, so an in-body note would make this file unlockable.)
Ar := @align(16) struct { a : u8 }
@align(16)
Ap := struct { a : u8 }
@align(16) mut AfterAlign := struct { a : u8 }
Ao := struct { a : u8 }

main := fn() -> u64 {
  if Rhs.size() != 7 { return 1 }
  if Pfx.size() != 7 { return 2 }
  if Same.size() != 7 { return 3 }
  if AfterAttr.size() != 7 { return 4 }
  if Plain.size() != 24 { return 5 }
  if Ar.align() != 16 { return 6 }
  if Ap.align() != 16 { return 7 }
  if AfterAlign.align() != 16 { return 8 }
  if Ao.align() != 8 { return 9 }
  p := Pfx(a = 1, b = 2, c = 3)
  if p.a != 1 { return 10 }
  if p.b != 2 { return 11 }
  if p.c != 3 { return 12 }
  return 42
}
