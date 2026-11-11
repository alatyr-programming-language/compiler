## e2e — #1576: the word-element twin of `ir_view_local_oob`. `pick(2)` indexes `s = xs[0..2]` of a
## `[u64; 4]` at its length, with the index a parameter. The read falls inside the backing array: a
## missing check reads `xs[2]` and answers 42 instead of trapping (Types §6.4).
## Measured on omen. With the view's `bound` removed from the IR, both functions are still IR-selected,
## and the program exited 42 on x86-ir, aarch64, riscv64 and wasm. With it, they trap: 132 / 133 /
## 133 / 134. On the parent (`cf159743`), `pick` was legacy-built and trapped there too.
pick := fn(i : usize) -> u64 {
  xs : [u64; 4] = [40, 41, 42, 43]
  s : Slice(u64) = xs[0..2]
  s[i]
}
main := fn() -> u64 {
  if pick(1) != 41 { return 1 }
  pick(2)
}
## expect: trap
