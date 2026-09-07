## e2e (#422) — CHECKED BOUNDS for a range slice used DIRECTLY as an index base. `xs[1..3]` is a
## TWO-element view of a four-element array, so index 2 is past its end even though the byte it
## would name (`xs[3]` = 55) is still inside the base array's own storage. Reading it would be the
## quiet half of #422's defect surviving the fix: a plausible neighbour word instead of a diagnostic.
##
## The recognizer above `emit_index_addr`'s tail has the view's RUNTIME length in hand (word 1 of the
## pair `emit_arr_slice_pair` materializes, `hi - lo`), so it compares the index against that length
## and traps — the same `cmpq`/`jb`/`ud2` every other checked index emits, and `jb` is unsigned, so a
## negative index traps too. Asserted as a TRAP (`run_x86_trap`, SIGILL = 132), not as an exit code:
## a trap ends the program, which is why this cannot live in `index_base_tail_controls`.
##
## The codes below exist only to name what a NON-trapping build did instead, so a regression is
## attributed immediately rather than read as "the fixture ran": 5 = it read `xs[3]` past the view,
## 6 = a zero / frame slot 0, 7 = some other word. None of them is the pass condition.
##
## x86_64-only by registration. The three non-x86 backends do not lower this shape at all; they emit
## a fail-loud trap for it (measured a133 / rv133 / wasm134), which is a different status than the
## checked 132 asserted here and is the acceptable half of correct-or-trap.
main := fn() -> u64 {
  xs : [u64; 4] = [71, 42, 93, 55]
  v := xs[1..3][2]
  if v == 55 { return 5 }
  if v == 0 { return 6 }
  7
}
