## Issue #771 — the forms of a direct `match` on a `Result(S, E)`-returning call where too few locals
## sit below the match scratch for the excess words to land on: the parent refused this program with a
## `selfhost:` abort at build time (exit 1) instead of running it. The scratch level is now as wide as
## the widest enum a direct call match in the function stages, so all four run: `return match`, a
## trailing value match, a 7-word enum returned in registers and a 9-word one returned through a
## hidden result pointer.
S4 := struct { f0 : u64, f1 : u64, f2 : u64, f3 : u64 }
S6 := struct { f0 : u64, f1 : u64, f2 : u64, f3 : u64, f4 : u64, f5 : u64 }
S8 := struct { f0 : u64, f1 : u64, f2 : u64, f3 : u64, f4 : u64, f5 : u64, f6 : u64, f7 : u64 }
r4 := fn(x : u64) -> Result(S4, u64) { Result(S4, u64).Ok(S4(f0 = 1, f1 = 2, f2 = 3, f3 = x)) }
r6 := fn(x : u64) -> Result(S6, u64) { Result(S6, u64).Ok(S6(f0 = x, f1 = 0, f2 = 0, f3 = 0, f4 = 0, f5 = x + 7)) }
r8 := fn(x : u64) -> Result(S8, u64) { Result(S8, u64).Ok(S8(f0 = x, f1 = 0, f2 = 0, f3 = 0, f4 = 0, f5 = 0, f6 = 0, f7 = x + 7)) }
ret := fn() -> u64 {
  return match r4(40) { Result::Ok(q) => { q.f3 } Result::Err(e) => { e } }
}
tail := fn() -> u64 {
  match r4(2) { Result::Ok(q) => { q.f3 } Result::Err(e) => { e } }
}
regs7 := fn() -> u64 {
  mut z : u64 = 0
  mut c : u64 = 0
  z = z + (match r6(3) { Result::Ok(q) => { q.f0 + q.f5 } Result::Err(e) => { 100 } })
  z + c
}
sret9 := fn() -> u64 {
  mut z : u64 = 0
  mut c : u64 = 0
  z = z + (match r8(4) { Result::Ok(q) => { q.f0 + q.f7 } Result::Err(e) => { 100 } })
  z + c
}
main := fn() -> u64 {
  if ret() != 40 { return 2 }
  if tail() != 2 { return 3 }
  if regs7() != 13 { return 4 }
  if sret9() != 15 { return 5 }
  42
}
