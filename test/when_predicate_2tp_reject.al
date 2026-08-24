## e2e (build_reject) — the FALSE branch of a MULTI-TYPE-PARAM `when size(V) <= 8` predicate over the
## SECOND type-parameter (Comptime §7.1/§9, CT-4/CT-5). `pair(K, V, x)` is guarded on `V`; here it is
## instantiated with `V = Big` (a 3-word struct, size 24 > 8), so the guard folds FALSE and the instance
## `pair__u64_Big` is AS-IF-ABSENT — never emitted. `main`'s call site still references it, so the build
## fails LOUD (undefined symbol at link). A SUCCEEDING build (the guard resolving against the WRONG
## type-param, e.g. the leading `K = u64`) is the regression to catch.
Big := struct { a : u64, b : u64, c : u64 }

pair := fn(K : type, V : type, x : u64) -> u64 when size(V) <= 8 { x }

main := fn() -> u64 {
  pair(u64, Big, 42)
}
