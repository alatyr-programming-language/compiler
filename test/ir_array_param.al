## e2e — #1626 (IR coverage, #980 step 3; #937's residual): a fixed-array parameter `xs : [T; N]` and an
## array field `s.arr` as array copy sources, built by the shared IR. Functions §2.1/§4.1: a parameter is
## logically a value (an `in` large aggregate is passed by reference, an `in out` one denotes the caller's
## place); Memory §5.9: an assignment copies the bits; Types §6.4: element `i` at `base + i * stride`.
## The IR builder refused a function with an array parameter ("parameter with a mode") and a call to one
## ("expr Call"), and an array field as a copy source ("expr Field"), so every backend kept its legacy
## emitter for them. MEASURED on the parent (exit code, native x86_64 and qemu/wasmtime), for the two
## #1626 shapes alone: `ys = xs` of an array parameter owed 16 and answered x86_64 132 (SIGILL), aarch64
## 224, riscv64 16, wasm 16; `ys = s.arr` owed 42 and answered x86_64 17, aarch64 5, riscv64 5, wasm 134.
## Each check below answers its own number when it fails; all passing answers 42.
## Expected exit 42. `x86-legacy` still answers 1 (no legacy-x86 fix, #980): a row of scripts/ir_diff.baseline.
## expect: run 42
S := struct { tag : u64, arr : [u64; 3] }

## #1626 shape 1: an array parameter copied whole.
from_param := fn(xs : [u64; 3]) -> u64 {
  ys : [u64; 3] = xs
  ys[1] + ys[2]
}
## #1626 shape 2: an array field copied whole.
from_field := fn(k : u64) -> u64 {
  s := S(tag = k, arr = [5, 30, 7])
  ys : [u64; 3] = s.arr
  ys[0] + ys[1] + ys[2]
}
## Elements read through the parameter by a checked runtime index, and its length.
sum := fn(xs : [u64; 4]) -> u64 {
  mut t : u64 = 0
  mut i : usize = 0
  while i < xs.len {
    t = t + xs[i]
    i = i + 1
  }
  t
}
## The parameter passed on to another array parameter.
sum_on := fn(xs : [u64; 4]) -> u64 { sum(xs) + 1 }
## No element write through an array parameter here: the builder refuses one (the parameter holds the
## caller's address whatever its direction, #1632), and scripts/e2e.sh `check_ir_build` asserts that.

main := fn() -> u8 {
  a : [u64; 3] = [1, 6, 10]
  if from_param(a) != 16 { return 1 }
  if from_field(9) != 42 { return 2 }
  b : [u64; 4] = [3, 4, 5, 6]
  if sum(b) != 18 { return 3 }
  if sum_on(b) != 19 { return 4 }
  if sum([10, 10, 10, 12]) != 42 { return 5 }
  s := S(tag = 1, arr = [2, 4, 40])
  if from_param(s.arr) != 44 { return 7 }
  42
}
