## Store-escape into a DEEP-NESTED field path of a module mut global (spec Memory §5.3.1: "a field of
## any aggregate that outlives R" — at arbitrary depth). `G.inner.p = ptr(x)` is a `FieldPathAssign`
## (a multi-level place `Field(Field(Var(G), inner), p)`) storing a dying stack address into a static
## place that outlives the local → forbidden upward flow. Check must reject (rc 1).
Inner := struct { p : ptr(u64) }
Outer := struct { inner : Inner }
SENTINEL := 0
mut G := Outer(inner = Inner(p = ptr(SENTINEL)))
leak := fn() {
  x := 5
  G.inner.p = ptr(x)
}
main := fn() -> u64 { 0 }
