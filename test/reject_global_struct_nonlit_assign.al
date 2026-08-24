## build_reject — a whole-value assignment of a NON-LITERAL aggregate (a fn return) to a mutable STRUCT
## global. The register/sret return-materialization the local Assign path uses is not modelled for a
## global `.data` destination, so a scalar store would drop every word past word 0 — the lower FAILS
## LOUD (panic) instead of silently miscompiling. (`G = R(…)` with a struct LITERAL is fully supported.)
R := struct { a : u64, b : u64 }
mut G := R(a = 0, b = 0)
mk := fn() -> R { R(a = 12, b = 30) }
main := fn() -> u64 {
  G = mk()
  G.a + G.b
}
