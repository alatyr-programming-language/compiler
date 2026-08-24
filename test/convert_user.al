## Types §4.6 / TYP-6 — a user CONVERSION-CONSTRUCTOR `@convert`. `Celsius` is a plain struct (NOT a
## brand, NOT a builtin conv_kind), so `Celsius(v)` cannot ride the builtin lattice or the brand path;
## it must dispatch to the single in-scope `@convert fn(u64) -> Celsius`. Binding `c := Celsius(42)`
## sizes `c` as the returned struct and a field read recovers the value.
Celsius := struct { deg : u64 }

mkc := @convert fn(x : u64) -> Celsius { return Celsius(deg = x) }

main := fn() -> u64 {
  c := Celsius(42)
  return c.deg
}
