## e2e — §2 OPERATOR OVERLOADING for the BITWISE glyphs `&`/`|`/`^` (kinds 34/35/36) over a USER
## type. `Bits` is a 1-word newtype; the three `@inline` operator fns route (via `operator_decl_idx`
## → `op_symbol` → `named_op_decl_idx`) exactly like `+`/`-`/`==` already do. Their bodies use the
## BUILT-IN bitwise on the u64 fields (no `Bits` operator over u64 exists, so those fall through to
## `andq`/`orq`/`xorq`). `(x | y) & mask ^ zero` = (34|8)&63^0 = 42. Confirms the parser NAME-GATE
## admits the three bitwise glyphs as operator-fn names (the only barrier — routing was already wired).
Bits := struct { v : u64 }
@inline & := fn(a : Bits, b : Bits) -> Bits { Bits(v = a.v & b.v) }
@inline | := fn(a : Bits, b : Bits) -> Bits { Bits(v = a.v | b.v) }
@inline ^ := fn(a : Bits, b : Bits) -> Bits { Bits(v = a.v ^ b.v) }
main := fn() -> u64 {
  x := Bits(v = 34)
  y := Bits(v = 8)
  mask := Bits(v = 63)
  zero := Bits(v = 0)
  r := ((x | y) & mask) ^ zero
  r.v
}
