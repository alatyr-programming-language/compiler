## fmt fixture — the AGGREGATE DECL surface. A `Decl` records a name, a `FieldDecl` list (name span,
## type span, arity) and nothing else, so fmt's canonical rebuild `Name := struct { f : T, … }`
## silently DROPPED everything the source writes AROUND that skeleton:
##   • the `:=`-to-`{` head — `@packed` / `@repr(i32)` (Types §8) and the `union` keyword (Types §6.3,
##     an untagged overlap reuses the enum-shaped decl) all came back as a bare `struct` / `enum`;
##   • a member attribute `@align(4) b : u32` (Types §8) — dropped, so `b` landed at byte 1;
##   • a field DEFAULT `x : u64 = 30` (Types §9.4) — source-scanned at construction, never stored;
##   • a discriminant PIN `A = 5` (Types §6.2) — re-scanned at emit, and its presence truncated the
##     rebuilt variant list to the first variant, so `B` vanished outright.
## Each of those is a DIFFERENT PROGRAM, not a different layout of the same one. The head is now
## copied verbatim, and a body holding `@`/`=`/`##` is copied verbatim too — not-formatting is safe.
## Returns 42.
Pk := @packed struct { a : u8, @align(4) b : u32, c : u8 }

Pair := struct { x : u64, y : u64 }

Wide := union { a(u64), p(Pair) }

Code := enum { A = 5, B = 10 }

Def := struct { x : u64 = 30, y : u64 }

## The checks below observe each dropped piece: `size(Pk) == 12` proves `@packed` AND `@align(4)`
## (a plain struct is 16, a plain packed one 6); `size(Wide) == 16` proves the untagged `union` (a
## tagged struct/enum would carry a tag word); the tag reads prove the pins; `Def(y = 12)` proves
## both the default and that a literal OMITTING a field keeps its remaining name.
main := fn() -> u64 {
  if size(Pk) != 12 { return 1 }
  if size(Wide) != 16 { return 2 }
  mut ca := Code.A
  ta := unchecked deref(unchecked bitcast(ptr(mut u64), unchecked bitcast(usize, ptr(ca))))
  mut cb := Code.B
  tb := unchecked deref(unchecked bitcast(ptr(mut u64), unchecked bitcast(usize, ptr(cb))))
  if ta != 5 { return 3 }
  if tb != 10 { return 4 }
  d := Def(y = 12)
  return d.x + d.y
}
