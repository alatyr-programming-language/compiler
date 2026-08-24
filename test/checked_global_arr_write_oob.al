## Checked-mode bounds trap for a MUTABLE-GLOBAL struct array element WRITE (I11 §358). `TAB[i] = P(…)`
## stored into `.data` at `LABEL + i*stride*8` with NO bounds check (the scalar-global write + both
## struct/scalar reads were likewise unchecked before this change), so an out-of-range index SILENTLY
## wrote out of bounds — memory corruption. Now traps (`cmpq $N; jb; ud2` — SIGILL, exit 132). x86_64.
P := struct { x : u64, y : u64 }
mut TAB := [P(x = 1, y = 2), P(x = 3, y = 4)]
main := fn() -> u64 {
  i : u64 = 8
  TAB[i] = P(x = 9, y = 9)
  return 0
}
