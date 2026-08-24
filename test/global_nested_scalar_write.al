## ROADMAP §4: WRITING a SCALAR field of a nested struct field of a mutable-global struct
## (`STATE.inner.a = v`, a FieldPathAssign). The default path writes a local frame slot, which for a
## global base is a silent no-op; the global path stores at LABEL + (fwo(inner)+fwo(a in P))*8.
## inner starts P(1,2); set a=30, b=7; 30 + 7 + n(5) = 42.
P := struct { a : u64, b : u64 }
Outer := struct { inner : P, n : u64 }
mut STATE := Outer(inner = P(a = 1, b = 2), n = 5)
main := fn() -> u64 {
  STATE.inner.a = 30
  STATE.inner.b = 7
  return STATE.inner.a + STATE.inner.b + STATE.n
}
