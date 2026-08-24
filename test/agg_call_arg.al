## e2e (lean-lower: a CALL returning a struct passed as a by-ref aggregate argument). `sum(mk())`
## where `mk() -> Pair` (2-word struct) feeds `sum(p : Pair)`: the call has no frame home, so
## `emit_arg` now materializes its register-returned words (%rax:%rdx:…) into the agg-temp block and
## passes the block's address (the by-ref convention, like a struct-literal arg). Was dropped/scalar-
## pushed → garbage → segfault. `40 + 2` → 42. (An enabler toward the UFCS `x.f().g()` / allocator
## `allocate(…).expect(…).idx` chains, whose remaining blockers are the generic-enum-ctor parser
## ambiguity + multiple-type-param inference.)
Pair := struct { a : u64, b : u64 }
mk := fn() -> Pair { Pair(a = 40, b = 2) }
sum := fn(p : Pair) -> u64 { p.a + p.b }
main := fn() -> u64 {
  sum(mk())
}
