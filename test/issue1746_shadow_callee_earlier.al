## #1755 review B3 / Declarations §6.1 — the `_later` twin with the module-level `f(x : u64)` and
## `pick(x : u64)` declared before their callers. The parameter `f` and the local `pick` still win
## within their scopes, so no module-level parameter list judges the calls' arguments. The seed
## 0.3.2 refused these calls with `type mismatch` (local x86_64 under emulation), judging the
## arguments against the shadowed module-level functions: the defect predates #1746.
S := struct { a : u64, b : u64 }
f := fn(x : u64) -> u64 { x }
pick := fn(x : u64) -> u64 { x }
g := fn(s : S) -> u64 { s.a }
apply := fn(f : fn(S) -> u64, s : S) -> u64 { f(s) }
main := fn() -> u64 {
  pick := g
  apply(g, S(a = 20, b = 1)) + pick(S(a = 22, b = 2))
}
## expect: run 42
