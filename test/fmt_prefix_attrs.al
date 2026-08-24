## e2e/fmt — a declaration's `@…` attribute run written on its OWN LINE above the declaration
## (Declarations §2.3 "a declaration MAY carry … `@`-attributes … always in prefix position";
## Grammar §3.2 `declaration ::= { modifier } binding`, `modifier ::= "pub" | "mut" | "comptime" |
## attribute` — no newline restriction). `fmt_decl_lead_attr` only ever looked at the decl's OWN line,
## so this spelling was ERASED: `@packed` newline `Pk := struct { … }` came back a naturally-aligned
## struct (24 bytes instead of 7) and `@align(16)` came back 8-aligned. That was invisible while the
## compiler still ignored the prefix spelling; the moment the layout lane started honouring it, fmt
## became a silent layout corrupter. This fixture locks the render, so it cannot regress silently.
Pfx := struct { a : u8, b : u16, c : u32 }

## a doc block sitting ABOVE the attribute line must still attach to the declaration — the attribute
## makes the comment→name gap non-blank, so `fmt_decl_anchor` has to anchor at the `@`, not the name.
@packed
Doc := struct { a : u8, b : u16, c : u32 }

## the same attribute in the decl's own-line prefix position, and in value position — all three
## spellings must survive a reformat identically.
@packed Same := struct { a : u8, b : u16, c : u32 }
Rhs := @packed struct { a : u8, b : u16, c : u32 }

## TWO attribute lines stacked above one declaration: the walk-back must take BOTH, not just the
## nearest one (taking only the nearest is what makes a naive fix non-idempotent — the outer one
## would be dropped on the second pass).
@align(16)
@packed
Both := struct { a : u8, b : u16, c : u32 }

## an attribute line above a `pub` declaration — the attribute precedes the visibility modifier.
@packed
pub Pb := struct { a : u8, b : u16, c : u32 }

main := fn() -> u64 {
  if Pfx.size() != 24 { return 1 }
  if Doc.size() != 7 { return 2 }
  if Same.size() != 7 { return 3 }
  if Rhs.size() != 7 { return 4 }
  if Both.size() != 7 { return 5 }
  if Both.align() != 16 { return 6 }
  if Pb.size() != 7 { return 7 }
  d := Doc(a = 1, b = 2, c = 3)
  if d.a != 1 { return 8 }
  if d.b != 2 { return 9 }
  if d.c != 3 { return 10 }
  return 42
}
