## #1375 — `t[i] = <str>` into a `[str; N]` local stores the whole two-word {ptr, len} pair (Types §7)
## when the index is a run-time value too, and a later `for` over the array sees the new element.
## Expected exit 42; each check returns its own code.
## Parent `032c4b55` of #1350 (x86_64, omen): built, and ran to 1 from both build-then-run and
## `alatyr run`: the run-time index row kept the old length 4 (written alone, the loop summed 142).
main := fn() -> u64 {
  mut t : [str; 3] = ["a", "bbbb", "cc"]
  i : usize = 1
  t[i] = "xyz"
  if t[1].len != 3 {
    return 1
  }
  if t[1] != "xyz" {
    return 2
  }
  mut u : [str; 3] = ["a", "bbbb", "cc"]
  u[1] = "xyz"
  mut n : u64 = 0
  for s in u {
    n = n * 10 + u64(s.len)
  }
  if n != 132 {
    return 3
  }
  42
}
## expect: run 42
