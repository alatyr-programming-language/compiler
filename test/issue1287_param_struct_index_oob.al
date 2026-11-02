## e2e (#1287) — an out-of-range index into a `[P; N]` PARAMETER whose element has a NON-SCALAR
## field traps (I11; Types §4.5, §6.4; Stdlib §3.5; CG-7). The bounds block that guarded a
## fixed-array parameter's struct element (`eek 2`) asked `index_plain_scalar_struct` first, so it
## fired only for a struct whose every field is a native scalar. A struct with a `str` field — the
## shape #1287's own `[str; N]` fix makes reachable through the same parameter ABI — fell through:
## `xs[i].b` with `i >= N` read past the caller's array and answered a word of it (measured 5 on
## the parent 01609666, where `[Q; 2]` with `Q(a : u64, b : u64)` already trapped 132).
##
## The first call is the IN-BOUNDS control: `xs[1].b` is 4 and must still answer 4. The second has
## `i == 2`, past the end of `[P; 2]`, and traps with the same `cmpq`/`jb`/`ud2` every other checked
## index emits (SIGILL, 132).
##
## 7 = the in-bounds control is wrong. That is not the pass condition.
P := struct { a : str, b : u64 }

f := fn(xs : [P; 2], i : usize) -> u64 { xs[i].b }

main := fn() -> u64 {
  t : [P; 2] = [P(a = "x", b = 3), P(a = "yy", b = 4)]
  if f(t, 1) != 4 { return 7 }
  mut i : usize = 1
  i = i + 1
  f(t, i)
}
## expect: trap
