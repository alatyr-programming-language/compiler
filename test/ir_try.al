## IR slice 4c (`docs/ir-slice-4.md` §3): `x?` on an `Option` and on a `Result`, built from the shared
## IR on the register twins. On success the value is the payload; on failure the function returns the
## failure in its own result type (`None`, or `Err` with the operand's error). Each check returns its
## own code on failure; 42 when all hold, on all four backends.
half := fn(x : u64) -> Option(u64) {
  if x % 2 == 1 { return Option(u64).None }
  Option(u64).Some(x / 2)
}
quarter := fn(x : u64) -> Option(u64) {
  h := half(x)?
  q := half(h)?
  Option(u64).Some(q)
}
chk := fn(x : u64) -> Result(u64, u64) {
  if x > 100 { return Result(u64, u64).Err(x) }
  Result(u64, u64).Ok(x + 1)
}
two := fn(x : u64) -> Result(u64, u64) {
  y := chk(x)?
  z := chk(y * 50)?
  Result(u64, u64).Ok(z)
}
main := fn() -> u64 {
  a : u64 = match quarter(40) { Some(v) => v; None => 100 }
  if a != 10 { return 1 }
  b : u64 = match quarter(6) { Some(v) => v; None => 7 }
  if b != 7 { return 2 }
  c : u64 = match two(1) { Ok(v) => v; Err(e) => e + 1000 }
  if c != 101 { return 3 }
  d : u64 = match two(3) { Ok(v) => v; Err(e) => e }
  if d != 200 { return 4 }
  a + b + 25
}
## expect: run 42
