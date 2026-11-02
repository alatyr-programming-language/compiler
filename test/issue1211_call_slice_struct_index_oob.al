## e2e (#1211, the review's blocking row) — an out-of-range index into a `Slice(P)` that a CALL
## returned traps on x86_64 (I11; Types §4.5, §6.4; Stdlib §3.5; CG-7). #1211 binds the bound call
## result `xs := pass(…)` as a slice VIEW instead of the nominal two-word `Slice` struct, so its
## elements are read through the view path; that path is bounds-checked by #1293, which this PR
## stacks on. Stacked alone, the same program read a third struct past a two-element view and answered
## its field — 6, where main refused it at build.
##
## The first read is the IN-BOUNDS control: `xs[1].b` is 4 and must still answer 4 (this PR's own
## fix). The second has `i == 2`, past the end of a two-element view, and traps with the same
## `cmpq`/`jb`/`ud2` every other checked index emits (SIGILL, 132).
##
## 7 = the in-bounds control is wrong. That is not the pass condition.
P := struct { a : u64, b : u64 }

pass := fn(s : Slice(P)) -> Slice(P) { s }

main := fn() -> u64 {
  t : [P; 3] = [P(a = 1, b = 2), P(a = 3, b = 4), P(a = 5, b = 6)]
  xs := pass(t[0..2])
  if xs[1].b != 4 { return 7 }
  mut i : usize = 1
  i = i + 1
  xs[i].b
}
## expect: trap
