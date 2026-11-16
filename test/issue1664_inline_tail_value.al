## e2e — #1664: an `@inline` call from a caller the shared IR does NOT build answers the body's
## FINAL EXPRESSION, not the value of its last STATEMENT. `main` holds an `f64`, which the IR builder
## refuses (`expr FloatLit`), so `main` stays on the legacy emitter and expands `mid` inside itself;
## `mid`'s body is a statement list ending in the expression `g(b)`. A block's value is its final
## expression (Control Flow §3, result typing), and Functions §3.3/§3.4 fill the `-> T` output from it
## exactly as `return g(b)` would — so the call owes 42. Before the fix the expansion emitted only the
## statements and pushed whatever %rax then held: `b`, which is 2.
g := fn(x : u64) -> u64 { x * 21 }
@inline mid := fn(k : u64) -> u64 {
  b : u64 = k + 1
  g(b)
}
main := fn() -> u8 {
  h : f64 = 1.5
  if h < 1.0 { return 3 }
  u8(mid(1))
}
## expect: run 42
