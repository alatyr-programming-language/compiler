## Seed-forms registry entry `try_inline_multiword` (scripts/seed_forms.tsv) — NOT a corpus fixture.
## The value of a `?` over a MULTI-WORD `Ok` payload used inline (`f()?.b`), strict_forms.md §7.
## #752; the tree takes every payload word since 1b5cd53, which the 0.2.4 seed predates: the seed reads
## the wrong payload word and this returns 0 there. The tree compiler must return 42.
T := struct { k : u64, a : u64, b : u64 }
f := fn(n : u64) -> Result(T, u64) { Result(T, u64).Ok(T(k = n, a = 20, b = 22)) }
g := fn() -> Result(u64, u64) {
  Result(u64, u64).Ok(f(1)?.a + f(2)?.b)
}
main := fn() -> u64 {
  match g() { Result::Ok(v) => { return v } Result::Err(e) => { return 1 } }
  0
}
