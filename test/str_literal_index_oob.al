## e2e (#405) — an out-of-range index into a str LITERAL must TRAP, not read past the literal's
## `.rodata` run. The literal's {ptr, len} pair carries the byte length, so the same checked-index
## `cmpq`/`jb`/`ud2` the str-LOCAL read uses applies here (I11 §358 / Types §6.4). The in-range
## read runs first, so a compiler that trapped on EVERY literal index would fail this row too.
## Expected shell status: 132 (SIGILL from the checked trap).
main := fn() -> u64 {
  if u64("abc"[2]) != 99 { return 100 }
  n := 7
  return u64("abc"[n])
}
