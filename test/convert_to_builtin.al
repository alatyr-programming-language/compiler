## Types §4.6 / TYP-6 — a user `@convert` whose TARGET is a BUILTIN-conv scalar name (`u64`). `Celsius`
## is a plain struct; `u64(c)` is NOT the scalar lattice (a struct is not a lattice scalar), so it must
## dispatch to the single in-scope `@convert fn(Celsius) -> u64`. Before this, the builtin-conv branch
## fired first and silently read the struct's WORD 0 (a miscompile — `u64(c)` returned `c.deg`, ignoring
## the @convert). Now a struct/enum operand routes to the @convert (or fails loud if none). 40 + 2 = 42.
Celsius := struct { deg : u64 }
to_u64 := @convert fn(c : Celsius) -> u64 { return c.deg + 2 }
main := fn() -> u64 {
  c := Celsius(deg = 40)
  return u64(c)
}
