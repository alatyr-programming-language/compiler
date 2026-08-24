## e2e (aggregate produced by an `if` EXPRESSION delivered DIRECTLY as a call ARGUMENT). `f(if c {
## Rec(12,30) } else {…})` where `f(x : Rec)` takes a 2-word struct BY-REF. The branch value has no
## frame home, so `emit_arg` now materializes each branch's value into a fresh agg-temp block (the
## down-growing by-ref layout) and passes the block's word-0 ADDRESS — like the struct-ctor arg case.
## Was: the whole `if` fell to the scalar default and passed ONE garbage word as the by-ref pointer →
## SEGFAULT (a Priority-1 silent miscompile). `12 + 30` -> 42.
Rec := struct { a : i64, b : i64 }
f := fn(x : Rec) -> i64 { x.a + x.b }
main := fn() -> u64 {
  c := true
  return u64(f(if c { Rec(a = 12, b = 30) } else { Rec(a = 0, b = 0) }))
}
