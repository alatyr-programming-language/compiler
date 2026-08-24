## Scoped-reference store-escape (spec Memory §5.3.1): storing `ptr(<fn-local>)` — a stack address that
## dies at the return — into a module-level `mut` global (a `static` place that OUTLIVES the local) is a
## forbidden upward flow, the dual of the return-dangling case. The check must reject (rc 1). `G` is
## pointer-typed (inferred) so the assign is type-correct → store-escape is the sole rejection reason.
SENTINEL := 0
mut G := ptr(SENTINEL)
leak := fn() {
  x := 5
  G = ptr(x)
}
main := fn() -> u64 { 0 }
