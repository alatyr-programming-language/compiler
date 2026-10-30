## #1177 — `for s in xs` over a `Slice(str)` PARAMETER binds each two-word `str` element in order
## (Control Flow, `for`; Stdlib §3.5). Expected exit 5, the lengths of "abc" and "de". The parent
## compiler copied the loop variable from the caller's {ptr, len} block instead of the elements and
## the program exited 1.
lens := fn(xs : Slice(str)) -> u64 {
  mut n : u64 = 0
  for s in xs {
    n += u64(s.len)
  }
  n
}

main := fn() -> u64 {
  t : [str; 2] = ["abc", "de"]
  lens(t[0..2])
}
