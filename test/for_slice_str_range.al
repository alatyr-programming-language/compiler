## #1177 — `for s in t[lo..hi]`, a range of a local `[str; N]` written in the loop header, binds the
## two-word `str` elements lo..hi. Expected exit 35: 5 for `t[0..2]` plus 10 * (2 + 1) for
## `t[1..3]`. The parent compiler read one word per element and the program exited 11.
main := fn() -> u64 {
  t : [str; 3] = ["abc", "de", "f"]
  mut n : u64 = 0
  for s in t[0..2] {
    n += u64(s.len)
  }
  mut m : u64 = 0
  for s in t[1..3] {
    m += u64(s.len)
  }
  n + m * 10
}
## expect: run 35
