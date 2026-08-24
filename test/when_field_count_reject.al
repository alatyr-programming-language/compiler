## e2e (build_reject) — the FALSE branch of a FIELD-COUNT `when` PREDICATE `when typeinfo(T).fields.len >= 2`
## (Comptime §7.1/§9, CT-4/CT-5). `pick(T, x)` is guarded on the concrete instance type's declared field
## count (the spec's `TypeInfo.Struct{fields:[Field]}` surface, appendix §4.1). Here it is instantiated with
## the 1-field struct `One`, whose `typeinfo(One).fields.len` = 1 (< 2), so the guard folds FALSE and the
## instance `pick__One` is AS-IF-ABSENT — never emitted. `main`'s call site still references it, so the build
## fails LOUD (undefined symbol at link). Without the field-count fold this would build (the guard ignored),
## so a SUCCEEDING build here is the regression to catch (`build_reject` asserts a non-zero build).
One := struct { a : u64 }

pick := fn(T : type, x : u64) -> u64 when typeinfo(T).fields.len >= 2 { x }

main := fn() -> u64 {
  pick(One, 42)
}
