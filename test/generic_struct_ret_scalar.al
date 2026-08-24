## e2e (§8 mono, aarch64 bind_param analogue) — a LEADING type-param generic that RETURNS its
## type-param instantiated at an ALL-SCALAR struct: `id(P, P(..))` binds `p : P`, and `p.x + p.y`
## reads the returned struct's fields. Exercises the struct-return type substitution on both the
## instance side (return + `v : T` param) and the caller side (result type of the generic call).
P := struct { x : u64, y : u64 }
id := fn(T : type, v : T) -> T { return v }
main := fn() -> u64 {
  p := id(P, P(x = 40, y = 2))
  return p.x + p.y
}
