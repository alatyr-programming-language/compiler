## e2e — Comptime §6.1/§10: the spec's own arity-≥2 capability query
## `resolves-query ::= "resolves" "(" fn-expr "," arg-list ")"` — does a call to `f` with THESE
## arguments resolve? Only the arity-1 spelling folded before, so the spec form fell to "cannot fold"
## and the `comptime if` emitted NEITHER branch (the function returned deterministic garbage).
g := fn(x : u64) -> u64 { return x + 1 }
main := fn() -> u64 {
  mut r : u64 = 0
  comptime if resolves(g, 1) { r = r + 6 } else { r = r + 100 }        ## right arity → true
  comptime if resolves(g, 1, 2) { r = r + 100 } else { r = r + 36 }    ## wrong arity → false
  comptime if resolves(nosuchfn, 1) { r = r + 100 } else { r = r + 0 } ## no such callee → false
  return r
}
