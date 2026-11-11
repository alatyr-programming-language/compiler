## e2e (#1287) — an out-of-range index into a `[str; N]` PARAMETER traps (I11; Types §4.5, §6.4;
## Stdlib §3.5; CG-7). #1287 gave a `str` element of a fixed-array parameter the two-word view
## element kind (`eek 4`, stride 2); no bounds block covered that kind on a parameter, so `xs[i]`
## with `i >= N` stopped being refused at build and read past the caller's array instead of trapping.
##
## The first call is the IN-BOUNDS control: `xs[1].len` is 2 and must still answer 2 — the check
## compares the raw index against the static N of the parameter's `[str; 2]` type and skips on
## `idx < N`. The second call has `i == 2`: past the end, so the same `cmpq`/`jb`/`ud2` every other
## checked index emits fires (SIGILL, 132). Asserted as a TRAP, not an exit code: a trap ends the
## program. On the parent 01609666 the second call returned a frame word (measured 0 for `i == 2`,
## and 236/238 from build-then-run, 62 under `alatyr run`, for `i == 5`).
##
## The codes below name only what a NON-trapping build answered, so a regression is attributed at
## once rather than read as "the fixture ran": 7 = the in-bounds control is wrong. That is not the pass
## condition.
f := fn(xs : [str; 2], i : usize) -> u64 { xs[i].len }

main := fn() -> u64 {
  t : [str; 2] = ["abc", "de"]
  if f(t, 1) != 2 { return 7 }
  mut i : usize = 1
  i = i + 1
  f(t, i)
}
## expect: trap
