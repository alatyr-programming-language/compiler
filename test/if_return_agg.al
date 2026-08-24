## e2e (an aggregate/str returned via an `if` EXPRESSION). Parallel to `return_match_agg`: a
## struct/tuple/str returned via `return if c { … } else { … }` (or the trailing form, no `return`)
## delivered {0}/empty — `emit_struct_value`/`emit_str_pair` have no `If` arm. A struct/tuple/str
## if-return now routes through `emit_return_value` (its `If` arm dispatches the cond + delivers each
## branch via the return convention). GUARDED to aggregate returns — a SCALAR if stays on `emit_gas`,
## and an enum if uses `emit_enum_value`'s own `If` arm (so scalar/enum ifs are byte-identical).
Pair := struct { a : u64, b : u64 }
ps := fn(c : bool) -> Pair { return if c { Pair(a = 30, b = 2) } else { Pair(a = 0, b = 0) } }
pt := fn(c : bool) -> (u64, u64) { return if c { (6, 2) } else { (0, 0) } }
ptr2 := fn(c : bool) -> (u64, u64) { if c { (1, 1) } else { (0, 0) } }   ## trailing if (no return)
nm := fn(c : bool) -> str { return if c { "hello" } else { "x" } }
main := fn() -> u64 {
  s := ps(true)             ## Pair(30, 2)
  t := pt(true)             ## (6, 2)
  r := ptr2(true)           ## (1, 1)
  n := nm(true)             ## "hello" (len 5)
  s.a + s.b + t.0 + t.1 + r.0 + r.1 + n.len - 5   ## 32 + 8 + 2 + 5 - 5 = 42
}
