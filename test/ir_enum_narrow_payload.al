## #1726: an enum built by the shared IR whose scalar payload component is a narrow signed integer
## crosses to a legacy-emitted caller with the canonical WORD the legacy reader loads, sign-extended.
## The builder wrote such a component at its own width into a zeroed word, so `-12345` arrived as
## `4294954951`: x86_64 answered 1 where 42 was due (parent; `x86-legacy` 42).
##   * `mk`, `mk8`, `mk16`: a variant literal with an `i32`, `i8` and `i16` payload;
##   * `pass`: `?` passing an `i32` error through to its own result;
##   * `sz`: an unsigned narrow payload, which must stay zero-extended.
## `lg_main` holds a float local, so the shared IR refuses it and it stays LEGACY-emitted; every other
## function here is IR-built (the e2e row pins that). Each check returns its own code; 42 when all hold.
## x86_64 only: the legacy `lg_main` traps on aarch64, riscv64 and wasm before any value is compared.
mk := fn(k : u64) -> Result(i32, u64) {
  if k == 0 { return Result(i32, u64).Err(5) }
  x : i32 = 0 - 12345
  Result(i32, u64).Ok(x)
}
mk8 := fn(k : u64) -> Option(i8) {
  if k == 0 { return Option(i8).None }
  x : i8 = 0 - 7
  Option(i8).Some(x)
}
mk16 := fn(k : u64) -> Option(i16) {
  if k == 0 { return Option(i16).None }
  x : i16 = 0 - 300
  Option(i16).Some(x)
}
bad := fn(k : u64) -> Result(u64, i32) {
  if k == 0 { x : i32 = 0 - 9 ; return Result(u64, i32).Err(x) }
  Result(u64, i32).Ok(k)
}
pass := fn(k : u64) -> Result(u64, i32) {
  v := bad(k)?
  Result(u64, i32).Ok(v + 1)
}
sz := fn(k : u64) -> Option(u32) {
  if k == 0 { return Option(u32).None }
  x : u32 = 4000000000
  Option(u32).Some(x)
}

lg_main := fn() -> u64 {
  w : f64 = 1.0
  match mk(1) { Ok(v) => { if i64(v) != (0 - 12345) { return 1 } } Err(e) => { return 2 } }
  match mk8(1) { Some(v) => { if i64(v) != (0 - 7) { return 3 } } None => { return 4 } }
  match mk16(1) { Some(v) => { if i64(v) != (0 - 300) { return 5 } } None => { return 6 } }
  match pass(0) { Ok(v) => { return 7 } Err(e) => { if i64(e) != (0 - 9) { return 8 } } }
  match pass(4) { Ok(v) => { if v != 5 { return 9 } } Err(e) => { return 10 } }
  match sz(1) { Some(v) => { if u64(v) != 4000000000 { return 11 } } None => { return 12 } }
  42
}

main := fn() -> u64 { lg_main() }
## expect(x86_64): run 42
