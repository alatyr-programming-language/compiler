## ROADMAP §4: preserved pointee types through pointer-returning calls.
## An INFERRED `p := get(…)` binding, where `get` is a non-generic fn whose declared return
## type is `ptr(Struct)`, must record `p` as a pointer-to-struct so `deref(p).field` reads the
## field through the pointer (not collapse onto p's own scalar slot). The annotated form
## (`p : ptr(Box) = …`) already worked; this closes the un-annotated case.
Box := struct { v : u64, w : u64 }
get := fn(p : ptr(Box)) -> ptr(Box) { return p }
main := fn() -> u64 {
  b := Box(v = 40, w = 2)
  p := get(ptr(b))
  ## bound form (`deref(p).f`) + inline form (`deref(get(…)).f`, no binding) — both must
  ## recover the pointee struct from the callee's declared return type.
  return deref(p).v + deref(get(ptr(b))).w
}
