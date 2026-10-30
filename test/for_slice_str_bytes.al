## #1177 — the `str` bound by `for s in xs` over a `Slice(str)` parameter is a whole view: its bytes
## are the element's bytes. Expected exit 15: (1 + 2 + 3) for "abc" and (4 + 5) for "de", each byte
## minus 96. The parent compiler bound a wrong view and the program exited 0.
sum := fn(xs : Slice(str)) -> u64 {
  mut n : u64 = 0
  for s in xs {
    for c in bytes(s) {
      n = n + u64(c) - 96
    }
  }
  n
}

main := fn() -> u64 {
  t : [str; 2] = ["abc", "de"]
  sum(t[0..2])
}
