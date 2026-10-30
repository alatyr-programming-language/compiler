## #1177 — `for s in t` over a local `[str; N]` array binds each two-word `str` element in order.
## Expected exit 32 (3 then 2). The parent compiler bound a one-word loop variable and the program
## exited 12.
main := fn() -> u64 {
  t : [str; 2] = ["abc", "de"]
  mut n : u64 = 0
  for s in t {
    n = n * 10 + u64(s.len)
  }
  n
}
