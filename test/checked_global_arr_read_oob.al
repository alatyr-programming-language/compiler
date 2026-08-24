## Checked-mode bounds trap for a MUTABLE-GLOBAL aggregate array element FIELD read (I11 §358). A global
## struct array `TAB[i].x` addresses `.data` at `LABEL + i*stride*8 + fieldidx*8` — this path had NO
## bounds check (only the scalar-global and frame paths did), so an out-of-range index SILENTLY read out
## of bounds. Now traps (`cmpq $N; jb; ud2` — SIGILL, exit 132), N = the array's static element count
## (`array_lit_info(...).nel`). x86_64-only. `i = 8` on a 2-element global array → trap.
P := struct { x : u64, y : u64 }
mut TAB := [P(x = 1, y = 2), P(x = 3, y = 4)]
main := fn() -> u64 {
  i : u64 = 8
  return TAB[i].x
}
