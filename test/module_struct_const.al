## e2e — MODULE-LEVEL const STRUCT field access (`ORIGIN.x` where `ORIGIN := Pt(x = …, y = …)`). The
## const's StructLit args are in field-declaration order, so a field read emits the arg at that
## field's declaration index — inline, no runtime storage. Returns 42 = 40 + 2.
Pt := struct { x : u64, y : u64 }
ORIGIN := Pt(x = 40, y = 2)
main := fn() -> u64 {
  ORIGIN.x + ORIGIN.y
}
