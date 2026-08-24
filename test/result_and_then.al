## e2e — `Result::and_then` (Stdlib §160): the monadic bind for `Result` (the analogue of the
## delivered `Option::and_then`), a THREE-type-parameter generic. `Ok(v)` → `f(v)` (itself a
## `Result(U, E)`), `Err(e)` → `Err(e)`. Exercises 3-type-param mono + a fn value returning a
## generic enum, bound + matched. Called bare (routed to `result::and_then`/ntpc-3). The `alloc::vec`
## reference triggers base-prelude injection.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

step := fn(x : u64) -> Result(u64, u64) {
  if x > 100 { return Result(u64, u64).Err(9) }
  return Result(u64, u64).Ok(x + 1)
}

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r0 := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r0))
  mut ar := arena_over(bp, 65536)
  mut v := alloc::vec::new(u64, ptr(ar))          ## triggers base-prelude injection
  alloc::vec::push(u64, v, 1).expect("p")

  mut r : u64 = 0

  ## Ok(20) → step → Ok(21)
  ra := and_then(u64, u64, u64, Result(u64, u64).Ok(20), step)
  match ra { Result::Ok(x) => { r = r + x } Result::Err(e) => { r = r + 500 } }

  ## Err(21) stays Err (f not applied), value unchanged
  rb := and_then(u64, u64, u64, Result(u64, u64).Err(21), step)
  match rb { Result::Ok(x) => { r = r + 500 } Result::Err(e) => { r = r + e } }

  ## r = 21 + 21 = 42
  if r == 42 { return 42 }
  1
}
