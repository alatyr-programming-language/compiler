## ROADMAP §4: WRITING a whole nested struct field at depth (`STATE.i.sub = P(…)`, a FieldPathAssign
## whose final field is itself a struct). global_place gives the cumulative offset; emit_global_agg_store
## materializes the struct and copies its words to .data ascending. 30 + 7 + n(5) = 42.
P := struct { a : u64, b : u64 }
Inner := struct { sub : P, k : u64 }
Q := struct { i : Inner, n : u64 }
mut STATE := Q(i = Inner(sub = P(a = 1, b = 2), k = 0), n = 5)
main := fn() -> u64 {
  STATE.i.sub = P(a = 30, b = 7)
  return STATE.i.sub.a + STATE.i.sub.b + STATE.n
}
