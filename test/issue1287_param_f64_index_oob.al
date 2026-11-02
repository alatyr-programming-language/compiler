## e2e (#1287) — an out-of-range index into a `[f64; N]` PARAMETER traps (I11; Types §4.5, §6.4;
## Stdlib §3.5; CG-7). A float element records the static N in `sns` but is not `eek 0`, so the
## scalar-element bounds block skipped it and no other block reached a parameter: `xs[i]` with
## `i >= N` read past the caller's array and answered a word of it (measured 0 on the parent
## 01609666, where `[u64; 2]` and `[u8; 2]` parameters already trapped 132).
##
## The first call is the IN-BOUNDS control: `xs[1]` is 2.0 and must still answer 2. The second has
## `i == 2`, past the end of `[f64; 2]`, and traps with the same `cmpq`/`jb`/`ud2` every other
## checked index emits (SIGILL, 132). 7 = the in-bounds control is wrong; that is not the pass
## condition.
f := fn(xs : [f64; 2], i : usize) -> u64 { u64(xs[i]) }

main := fn() -> u64 {
  t : [f64; 2] = [1.0, 2.0]
  if f(t, 1) != 2 { return 7 }
  mut i : usize = 1
  i = i + 1
  f(t, i)
}
## expect: trap
