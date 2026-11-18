## #1755 review B3 / Declarations §6.1 — an inner name wins within its scope. A parameter `f` and a local
## `pick`, each holding a function of `S`, are called by those names while module-level `f(x : u64)` and
## `pick(x : u64)` are declared after their callers. The calls name the parameter and the local, so
## no module-level parameter list judges their arguments. #1755's first head (e43bebee, native x86_64
## on omen) refused both calls with `type mismatch`; the parent answered 42.
S := struct { a : u64, b : u64 }
g := fn(s : S) -> u64 { s.a }
apply := fn(f : fn(S) -> u64, s : S) -> u64 { f(s) }
main := fn() -> u64 {
  pick := g
  apply(g, S(a = 20, b = 1)) + pick(S(a = 22, b = 2))
}
f := fn(x : u64) -> u64 { x }
pick := fn(x : u64) -> u64 { x }
## expect: run 42
