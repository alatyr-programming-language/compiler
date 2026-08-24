## §3/CT (monomorph dedup): the SAME generic instance reached two ways whose implicit type-arg is
## inferred from a struct LITERAL must dedup to ONE emitted definition. `h(W(v=40))` infers T=W from
## the literal, whose name span sits right before `(`, so a naive instance tag makes `typearg_at`
## mis-read the field list as type-args; `g(W, W(v=2))`'s transitive `h(w)` tags T=W cleanly (off a
## param). Both are `h__W` — without a canonical (decl-name) tag they compare unequal and emit a
## DUPLICATE `h__W` symbol (assembler error). 40 + 2 = 42.
W := struct { v : u64 }

h := fn(T : type, w : T) -> u64 {
  return w.v
}

g := fn(T : type, w : T) -> u64 {
  return h(w)
}

main := fn() -> u64 {
  x := h(W(v = 40))
  y := g(W, W(v = 2))
  return x + y
}
