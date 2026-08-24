## e2e — fail-loud: a GENERIC-CONSTRUCTION-shaped literal `Name(args)(field = …)` whose head
## `Name` resolves to NO declared struct, type-function, or type alias. The parser erases the
## type-arg list (`X(128)` → a `StructLit(X, …)`), and the lower's struct-decl lookup then MISSED —
## every field fell to the scalar path and a bare `ArrayLit` emitted `$0`, so the whole value was a
## SILENT zero struct that COMPILED. An unresolvable construction head must FAIL LOUD at build
## time instead. (The legitimate heads keep working: a local type-fn `uint(192)(…)`, the prelude
## alias `u128(…)`, a plain `S(…)`.) build_reject: non-zero build rc.
main := fn() -> u64 {
  x := X(128)(words = [1, 2])
  x.words[0]
}
