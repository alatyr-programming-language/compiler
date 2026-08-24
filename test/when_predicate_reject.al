## e2e (build_reject) — the FALSE branch of a generic `when size(T)` PREDICATE (Comptime §7.1/§9,
## CT-4/CT-5). `pick(T, x)` is guarded `when size(T) <= 8`; here it is instantiated with `Big`
## (a 3-word struct, size 24 > 8), so the guard folds FALSE and the instance `pick__Big` is
## AS-IF-ABSENT — never emitted. `main`'s call site still references the `pick__Big` symbol, so the
## build fails LOUD (undefined symbol at link) — exactly the spec's "the declaration does not exist
## for this `T`". Without the instantiation-time guard fold this would build (the guard ignored), so a
## SUCCEEDING build here is the regression to catch (`build_reject` asserts a non-zero build).
Big := struct { a : u64, b : u64, c : u64 }

pick := fn(T : type, x : u64) -> u64 when size(T) <= 8 { x }

main := fn() -> u64 {
  pick(Big, 42)
}
