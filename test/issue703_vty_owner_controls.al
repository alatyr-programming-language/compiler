## e2e — issue #703 control for the residual slice: owners with NO declared type span, whose member reads
## are legal (Types §6.1, §6.4) and must keep compiling now that a span-less owner is judged by its
## recorded value type — an unannotated struct local, tuple, str, struct global and str global, and a
## field through a `ptr(P)` parameter. It answers 18 = 5 + 3 + 1 + 2 + 2 + 5 on the parent and after.
P := struct { x : u64 }
CFG := P(x = 2)
NAME := "ab"
sum := fn(q : ptr(P)) -> u64 { q.x }
main := fn() -> u64 {
  r := P(x = 5)
  t := (3, 4)
  w := "k"
  s := sum(ptr(r))
  r.x + u64(t.0) + u64(w.len) + CFG.x + u64(NAME.len) + s
}
## expect: run 18
