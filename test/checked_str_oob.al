## Checked-mode STR byte-access bounds trap (I11 / CG-7): `s[i]` on a `str`/str-view local reads a byte
## at `ptr + i` and now compares the runtime index against the str's len word — out of range traps via
## `ud2` (→ SIGILL). `"abc"` has len 3; a RUNTIME index `i = 10` is out of range → trap. x86_64-only
## (the guard is in the x86_64 lower), registered `run_x86`. Exit 132 (128 + SIGILL 4).
main := fn() -> u64 {
  s := "abc"
  i := 10
  return u64(s[i])
}
