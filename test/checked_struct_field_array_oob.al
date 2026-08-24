## Checked-mode bounds trap for an ARRAY FIELD of a struct (`s.xs[i]`, xs : [T; N]) — I11 §358. The
## nested-place index path (`field_index_base`) computed the element address `field-word-0 - i*8` with
## NO bounds check, so `s.xs[i]` with an out-of-range `i` read/wrote out of bounds SILENTLY. Now the
## field's static length N (from its declared type `[T; N]`) is carried on `FldIxBase.flen` and an
## out-of-range index traps (`cmpq $N; jb; ud2` — SIGILL, exit 132). x86_64. `i = 9` on `[u64; 3]` → trap.
S := struct { xs : [u64; 3], n : u64 }
main := fn() -> u64 {
  s := S(xs = [10, 20, 30], n = 3)
  i : u64 = 9
  return s.xs[i]
}
