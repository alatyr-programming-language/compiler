## #1177 — `for s in f(...)` over a call declared to return `Slice(str)` binds its two-word `str`
## elements. Expected exit 32 (3 then 2). The parent compiler read one word per element and the
## program exited 1.
pass := fn(t : Slice(str)) -> Slice(str) {
  t
}

main := fn() -> u64 {
  t : [str; 2] = ["abc", "de"]
  mut n : u64 = 0
  for s in pass(t[0..2]) {
    n = n * 10 + u64(s.len)
  }
  n
}
## expect: run 32
