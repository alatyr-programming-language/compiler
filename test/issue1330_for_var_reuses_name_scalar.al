## #1330 — the scalar twin: an iterable `for x in xs` after `x : u64 = 9` in an ended sibling scope
## (Declarations §6.1). The loop sums every element (Control Flow §6) and `w` keeps its value.
## NON-VACUOUS: on the parent da8f96af (native x86_64, tree Stage1) this answers 2 (`w` overwritten by
## the hidden loop index), on x86_64 and on aarch64, riscv64 and wasm alike.
main := fn() -> u64 {
  xs : [u64; 3] = [1, 3, 5]
  c := xs[0]
  if c == 1 {
    x : u64 = 9
    if x != 9 { return 9 }
  }
  w : u64 = 1000
  mut t : u64 = 0
  for x in xs {
    t += x
  }
  if t != 9 { return 1 }
  if w != 1000 { return 2 }
  42
}
## expect: run 42
