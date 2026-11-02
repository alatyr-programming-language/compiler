## e2e (#1287, and the same hole filed as #1404) — an out-of-range index into an `[E; N]` PARAMETER
## traps (I11; Types §4.5, §6.4; Stdlib §3.5; CG-7). A fixed-array parameter's slot is the caller's
## element-0 pointer and it owns no length word, so its only bound is the static N of its type; the
## bounds blocks in `emit_index_addr` reached an enum element (`eek 3`) only through `sns`, which a
## fixed-array parameter spends on the element TYPE span instead. So `xs[i]` with `i >= N` read past
## the caller's array and answered a word of it (measured 0 on the parent 01609666) where the
## word-element and byte-element kinds already trapped.
##
## The first call is the IN-BOUNDS control: `xs[1]` is `E.B(2, 3)` and must still answer 5. The
## second has `i == 2`, past the end of `[E; 2]`, and traps with the same `cmpq`/`jb`/`ud2` every
## other checked index emits (SIGILL, 132).
##
## 7 = the in-bounds control is wrong. That is not the pass condition.
E := enum { A(u64), B(u64, u64) }

f := fn(xs : [E; 2], i : usize) -> u64 {
  mut v : u64 = 0
  match xs[i] {
    E::A(x) => { v = x }
    E::B(x, y) => { v = x + y }
  }
  v
}

main := fn() -> u64 {
  t : [E; 2] = [E.A(1), E.B(2, 3)]
  if f(t, 1) != 5 { return 7 }
  mut i : usize = 1
  i = i + 1
  f(t, i)
}
## expect: trap
