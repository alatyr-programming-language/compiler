## fmt fixture — STRUCT-LITERAL field names (Types §9.3, construction is by-name). The parser keeps
## only the positional VALUE args of `S(f = v, …)`, so fmt has to re-attach the names. It used to
## take them from the struct DECL's FieldDecl list, positionally — which is right only when the
## literal names every field in DECLARATION ORDER. `compile_file_fmt` parses with a NULL struct
## table on purpose (fmt must preserve the order as written), so the by-name reorder is OFF and the
## stored args are in SOURCE order. Every other literal was therefore RELABELLED — the values stay
## put and the NAMES move, the quietest possible miscompile:
##   P(y = 2, x = 40)  ->  P(x = 2, y = 40)     the two fields swap values
##   D(b = 3)          ->  D(a = 3)             a literal omitting a defaulted field
##   D(c = 1, b = 2)   ->  D(a = 1, b = 2)
## The names are always spelled in the source, so fmt now scans them from the literal itself and
## only falls back to the decl when the field list cannot be located. Returns 42.
P := struct { x : u64, y : u64 }

D := struct { a : u64 = 5, b : u64, c : u64 = 7 }

main := fn() -> u64 {
  p := P(y = 2, x = 29)
  d := D(b = 3)
  e := D(c = 1, b = 2)
  if p.x != 29 { return 1 }
  if p.y != 2 { return 2 }
  if d.a != 5 { return 3 }
  if d.b != 3 { return 4 }
  if d.c != 7 { return 5 }
  if e.a != 5 { return 6 }
  if e.c != 1 { return 7 }
  return p.x + p.y + e.b + d.b + e.c + d.a
}
