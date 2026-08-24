## e2e — §2 operator overloading where the operator fn has NO `@inline` marker and RETURNS the user
## type (`T + T -> T`). The operator resolver matched only `@inline` glyph fns, so a plain
## `+ := fn(a : Num, b : Num) -> Num` never routed: `a + b` fell through to the built-in scalar
## lowering over the struct words and the `r := a + b` binding stayed a SCALAR slot, so `r.v` read
## garbage (exit 0) — a SILENT MISCOMPILE (the `@inline` twin of this exact program,
## operator_struct_result.al, always worked). The fix resolves a non-inline operator as a fallback
## (the @inline match still wins) and expands it at the site through the same machinery, so the
## binding is sized as `Num` and `r.v` reads the field. 20 + 22 -> 42.
Num := struct { v : u64 }
+ := fn(a : Num, b : Num) -> Num { Num(v = a.v + b.v) }
main := fn() -> u64 {
  a := Num(v = 20)
  b := Num(v = 22)
  r := a + b
  r.v
}
