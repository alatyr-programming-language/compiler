## TYP-8 / spec Types §9.4 — STRUCT-FIELD DEFAULTS `x : T = <expr>`. A struct field may carry a
## construction-time default; when a literal OMITS that field, the default value is used (applied AT
## CONSTRUCTION, at ANY position — not just trailing). Built on the by-name reorder: the default is
## SOURCE-SCANNED at the decl (no `FieldDecl` growth) and RE-LEXED at each construction site. A provided
## field always OVERRIDES its default. Returns 42. Correct on every backend (a parse desugar) → `run`.
P := struct { x : u64 = 40, y : u64 }

## a MIDDLE defaulted field, omitted, must be filled while the later field still lands right.
T := struct { a : u64, b : u64 = 7, c : u64 }

## two defaults; either or both may be omitted or overridden.
W := struct { p : u64 = 2, q : u64 = 3 }

main := fn() -> u64 {
  ## (1) omit a DEFAULTED field → its default value; provide the other.
  p1 := P(y = 2)
  if p1.x != 40 { return 1 }
  if p1.y != 2 { return 2 }

  ## (2) PROVIDE the defaulted field → the provided value OVERRIDES the default.
  p2 := P(x = 5, y = 2)
  if p2.x != 5 { return 3 }
  if p2.y != 2 { return 4 }

  ## (3) a MIDDLE defaulted field omitted (not trailing) → filled, later field still lands right.
  t := T(a = 1, c = 3)
  if t.a != 1 { return 5 }
  if t.b != 7 { return 6 }
  if t.c != 3 { return 7 }
  if t.a * 100 + t.b * 10 + t.c != 173 { return 8 }

  ## (4) by-name reorder STILL correct with a default present (write y before x).
  p3 := P(y = 6, x = 5)
  if p3.x != 5 { return 9 }
  if p3.y != 6 { return 10 }

  ## (5) two-default struct, ONE field provided → the other filled from its default (both orders).
  w1 := W(p = 5)
  if w1.p != 5 { return 11 }         ## provided overrides default
  if w1.q != 3 { return 12 }         ## omitted → default 3

  w2 := W(q = 9)
  if w2.p != 2 { return 13 }         ## omitted → default 2
  if w2.q != 9 { return 14 }         ## provided overrides default

  return 42
}
