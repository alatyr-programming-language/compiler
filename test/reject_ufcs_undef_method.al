## e2e REJECT (check) — an UNDEFINED callee reached by UFCS: `v.nosuchmethod(1)` names no declared fn,
## no local, no struct field and no built-in. ROADMAP §1(b) rejects that at CHECK time rather than at
## LINK; the direct `nosuchmethod(v, 1)` always was. Through the UFCS spelling the undefined-callee check
## never ran — an `EnumLit` carries a variant NAME, which is not resolved against the fn namespace.
V := struct { n : u64 }

main := fn() -> u64 {
  v := V(n = 1)
  v.nosuchmethod(1)
}
