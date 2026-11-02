## e2e (#1211, the review's blocking row) — an out-of-range index into a `Slice(str)` that a CALL
## returned traps on x86_64 (I11; Types §4.5, §6.4; Stdlib §3.5; CG-7). #1211 binds the bound call
## result `r := passs(…)` as a slice VIEW, so its elements are read through the view path; that path
## is bounds-checked by #1293, which this PR stacks on. Without #1293 the same program read the third
## string past a two-element view and answered its length — 3, where main trapped.
##
## The first call is the IN-BOUNDS control: `r[1].len` is 2 and must still answer 2 (this PR's own
## fix). The second has `i == 2`, past the end of a two-element view, and traps with the same
## `cmpq`/`jb`/`ud2` every other checked index emits (SIGILL, 132).
##
## 7 = the in-bounds control is wrong. That is not the pass condition.
passs := fn(t : Slice(str)) -> Slice(str) { t }

main := fn() -> u64 {
  ss : [str; 3] = ["abc", "de", "f"]
  r := passs(ss[0..2])
  if r[1].len != 2 { return 7 }
  mut i : usize = 1
  i = i + 1
  r[i].len
}
## expect: trap
