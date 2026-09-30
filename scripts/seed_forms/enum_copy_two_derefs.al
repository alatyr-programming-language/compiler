## Seed-forms registry entry `enum_copy_two_derefs` (scripts/seed_forms.tsv) — NOT a corpus fixture.
## A whole multi-word enum copied through two derefs, `deref(dst) = deref(src)`. `src/ast.al` records
## this as a SEED limitation and copies word by word instead. Measured, the tree compiler gets it wrong
## too: neither the tag nor the payload is copied, and this returns 1 on both. State `tree`, #790.
## Due: 42.
E := enum { Num(u64), Var(u64, u64), Pair(u64, u64, u64) }
cp := fn(dst : ptr(mut E), src : ptr(E)) { deref(dst) = deref(src) }
rd := fn(p : ptr(E)) -> u64 {
  match deref(p) {
    E::Num(x) => { 1 }
    E::Var(s, n) => { s + n }
    E::Pair(x, y, z) => { 3 }
  }
}
main := fn() -> u64 {
  mut a : E = E.Num(1)
  b : E = E.Var(30, 12)
  cp(ptr(mut a), ptr(b))
  rd(ptr(a))
}
