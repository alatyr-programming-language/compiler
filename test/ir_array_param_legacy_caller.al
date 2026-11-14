## e2e — #1626, #1641's review (B1): a fixed-array parameter function called by a LEGACY caller with an
## array field, a nested array field or an array element as the argument. Functions §2.1/§4.1: the callee
## reads the caller's array; Types §6.4: element `i` at `base + i * stride`.
## `main` holds an `f64` local, which the shared IR does not build, so every backend emits it with its
## legacy emitter. The aarch64 and riscv64 legacy emitters pass `s.arr`, `o.inner.arr` and `m[1]` by the
## value of the array's FIRST ELEMENT instead of its address. While the callee stayed legacy on the
## twins it was a fail-loud stub (#1194) and the program trapped (aarch64 and riscv64 133, wasm 134).
## Built from the IR, the callee dereferenced that element: MEASURED on the IR-built head (`fe154e23`),
## aarch64 and riscv64 answered 139 (SIGSEGV; a wrong value when the element holds a mapped address).
## So a function with an array parameter is IR-built only when every function that may call it is
## (`ir::ap_plan_begin`), and the callee here keeps its legacy emission on every target: x86_64 answers
## 42 (its legacy caller passes the address), the twins trap as before (`scripts/known-deviations.tsv`,
## #1194). The callee's name appears in no comment above: one outside every declaration would hold it
## to legacy by itself, and this program would no longer test that its legacy caller does.
## Each check below answers its own number when it fails; all passing answers 42.
## expect: run 42
S := struct { tag : u64, arr : [u64; 3] }
O := struct { k : u64, inner : S }

rd := fn(xs : [u64; 3]) -> u64 { xs[0] * 100 + xs[1] * 10 + xs[2] }
rd_io := fn(in out xs : [u64; 3]) -> u64 { xs[0] * 100 + xs[1] * 10 + xs[2] }

main := fn() -> u8 {
  z : f64 = 1.0
  if z > 2.0 { return 9 }
  s := S(tag = 1, arr = [0, 4, 2])
  if rd(s.arr) != 42 { return 1 }
  o := O(k = 1, inner = S(tag = 2, arr = [0, 4, 2]))
  if rd(o.inner.arr) != 42 { return 2 }
  m : [[u64; 3]; 2] = [[7, 7, 7], [0, 4, 2]]
  if rd(m[1]) != 42 { return 3 }
  mut t := S(tag = 3, arr = [0, 4, 2])
  if rd_io(t.arr) != 42 { return 4 }
  42
}
