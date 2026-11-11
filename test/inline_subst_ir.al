## Issue #1074 — Codegen §3.5 item 3 (spec v1.9.0): a function marked `@inline` is "substituted at every
## direct call site", and the substituted body "never reverts to a `call`". Every backend that emits from the
## shared IR inherits the substitution from the IR builder, so the e2e helper reads the `x86-ir` dump and the
## aarch64, riscv64 and wasm text for a call to any of the four callees below, then runs the program.
## Shapes: `sum3` is the statement spelling (a lone `return`), `twice` the tail spelling, `flip` a unary
## operator, `wrapadd` writes its own `unchecked` (200 + 98 wraps to 42 at u8).
## Measured on the parent (cdcecb5c): each of x86-ir, aarch64, riscv64 and wasm emitted 4 calls in `main`,
## one to each callee, where 0 are due; the program still built and ran to 42 on x86-ir.
sum3 := @inline fn(a : u64, b : u64, c : u64) -> u64 {
  return a + b + c
}
twice := @inline fn(x : u64) -> u64 { x + x }
flip := @inline fn(b : bool) -> bool { not b }
wrapadd := @inline fn(x : u8, y : u8) -> u8 { unchecked (x + y) }
main := fn() -> u64 {
  mut ok : u64 = 0
  if sum3(10, 12, 20) == 42 { ok = ok + 1 }
  if twice(21) == 42 { ok = ok + 1 }
  if flip(false) { ok = ok + 1 }
  if wrapadd(200, 98) == 42 { ok = ok + 1 }
  if ok == 4 { return 42 }
  ok
}
## expect: run 42
