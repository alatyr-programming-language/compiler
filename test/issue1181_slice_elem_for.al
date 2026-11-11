## #1181 — `for s in t` over a `[Slice(u8); N]` local, and over a `Slice(Slice(u8))` parameter, binds
## each element's own two-word {ptr, len} pair (Types §7; Control Flow §6), so `s.len` is the length that
## element was built with. Expected exit 42; each check returns its own code.
## Parent `032c4b55` of #1350 (x86_64, omen): built, and ran to 1 from both build-then-run and
## `alatyr run` (written alone, the local loop and the parameter loop each summed 1 where 32 was due).
lens := fn(xs : Slice(Slice(u8))) -> u64 {
  mut n : u64 = 0
  for s in xs {
    n = n * 10 + u64(s.len)
  }
  n
}

main := fn() -> u64 {
  a : [u8; 3] = [1, 2, 3]
  b : [u8; 2] = [4, 5]
  t : [Slice(u8); 2] = [a[0..3], b[0..2]]
  mut n : u64 = 0
  for s in t {
    n = n * 10 + u64(s.len)
  }
  if n != 32 {
    return 1
  }
  if lens(t[0..2]) != 32 {
    return 2
  }
  42
}
## expect: run 42
