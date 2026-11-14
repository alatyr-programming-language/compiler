## e2e — #1626, #1641's review (B2): a fixed-array parameter function handed an array a LEGACY function
## copied. Memory §5.9: an assignment copies the bits; Functions §4.1: the callee reads the caller's array.
## `lg` and `main` hold an `f64` local, which the shared IR does not build, so every backend emits them
## with its legacy emitter, whose array copies `ys = xs` (of a parameter) and `b = a` (of a local) are
## wrong on the twins (#1626). While the callee stayed legacy there it was a fail-loud stub (#1194) and
## the program trapped (aarch64 and riscv64 133, wasm 134). Built from the IR, the callee ran on the bad
## copy: MEASURED on the IR-built head (`fe154e23`), aarch64 and riscv64 answered 1 and wasm 3 — wrong
## values. So a function with an array parameter is IR-built only when every function that may call it
## is (`ir::ap_plan_begin`), and the callee here keeps its legacy emission on every target: x86_64
## answers 42, the twins trap as before (`scripts/known-deviations.tsv`, #1194). The callee's name
## appears in no comment above (see `ir_array_param_legacy_caller.al`).
## Each check below answers its own number when it fails; all passing answers 42.
## expect: run 42
rd := fn(xs : [u64; 3]) -> u64 { xs[0] * 100 + xs[1] * 10 + xs[2] }

lg := fn(k : u64, xs : [u64; 3]) -> u64 {
  z : f64 = 1.0
  if z > 2.0 { return 0 }
  ys : [u64; 3] = xs
  rd(ys) + k
}

main := fn() -> u8 {
  z : f64 = 1.0
  if z > 2.0 { return 9 }
  a : [u64; 3] = [0, 3, 7]
  if lg(5, a) != 42 { return 1 }
  mut b : [u64; 3] = a
  b[1] = 4
  b[2] = 2
  if rd(b) != 42 { return 2 }
  if rd(a) != 37 { return 3 }
  42
}
