## Checked-mode bounds trap for an ARRAY FIELD of a MUTABLE MODULE-LEVEL struct (`gg.xs[i]`,
## xs : [T; N]) -- Types 6.4 (the index is bounds-checked by default) / I11 358. This arm lowered
## through `global_field_off`, which addressed the element at `LABEL + (off + i)*8(%rip)` with NO
## `cmpq`/`ud2` guard, so an out-of-range index read the NEXT FIELD of the same global and returned
## it as an ordinary value. The field's static length N now feeds the same check the direct
## mutable-global-array arm already emitted: SIGILL, shell status 132.
##
## FAILURE-FIRST: measured on the parent compiler this program exited 99 -- the neighbouring
## `guard` field, a plausible-looking u64 that is NOT a wrong-value tell on its own (issue #386),
## which is why it is deliberately far from every in-range element and from 42.
##
## The in-range row runs FIRST, so a compiler that trapped on every `gg.xs[i]` would fail this row
## too rather than pass by over-trapping. The three in-range elements are non-zero and pairwise
## distinct, so a one-off address error is visible as a wrong exit rather than a silent match.
##
## Registered `run_x86`: a64/rv64/wasm emit a fail-loud `unsupported index` trap for this whole
## shape today (in range as well as out), so the row is deliberately outside the cross-target
## sweeps. `i` is a runtime-valued binding so the index is not comptime-folded away.
G := struct { xs : [u64; 3], guard : u64 }
mut gg := G(xs = [10, 20, 30], guard = 99)
main := fn() -> u64 {
  a : u64 = 0
  if gg.xs[a] != 10 { return 100 }
  b : u64 = 1
  if gg.xs[b] != 20 { return 101 }
  c : u64 = 2
  if gg.xs[c] != 30 { return 102 }
  i : u64 = 3
  return gg.xs[i]
}
