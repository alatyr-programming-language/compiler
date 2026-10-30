## #986 — the VALUE of `<call>.expect(m)` used directly as an argument, where the payload is a
## two-word struct. The inline unwrap delivers one payload word in value position, so the parent built
## this program and passed `sum` a struct whose second field nothing wrote. The head refuses the shape at
## build time and names the issue; binding first (`s := mk().expect("s")`, then `sum(s)`) is the form
## that delivers every word, and `issue986_expect_call_receiver` covers it.
##
## Expected: the build is rejected, with the diagnostic naming #986 and leaving no artifact.
##
## Parent `55fa477` (x86_64, omen): built rc 0, and the program died with SIGSEGV (rc 139).
S := struct { a : u64, b : u64 }
mk := fn() -> Result(S, u64) { return Result(S, u64).Ok(S(a = 1, b = 41)) }
sum := fn(s : S) -> u64 { return s.a + s.b }
main := fn() -> u64 {
  return sum(mk().expect("s"))
}
