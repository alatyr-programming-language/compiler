## e2e — #1576: an index of a slice view LOCAL built by the shared IR is checked against the view's
## runtime length word, not the backing array's (Types §6.4: an out-of-range index traps; Stdlib
## appendix §3.5). `pick(2)` indexes `s = xs[1..3]` at its length, with the index a parameter, so no
## constant folds it away. The element is `u32`, so the stride (4 bytes) is exercised too. The read
## falls INSIDE the backing array: a missing check reads `xs[3]` and answers 42 instead of trapping.
## The in-range call before it answers normally, so the trap is the index check and not the function.
## Measured on omen. With the view's `bound` removed from the IR, `pick` and `main` are still selected
## from the shared IR and the program exited 42 on x86-ir, aarch64, riscv64 and wasm (a read past the
## view). With it, they trap: 132 / 133 / 133 / 134. On the parent (`cf159743`), `pick` was not
## IR-built, and the legacy emitters' own bounds check trapped (132 / 133 / 133 / 134).
pick := fn(i : usize) -> u32 {
  xs : [u32; 4] = [10, 20, 30, 42]
  s : Slice(u32) = xs[1..3]
  s[i]
}
main := fn() -> u64 {
  if pick(1) != 30 { return 1 }
  u64(pick(2))
}
## expect: trap
