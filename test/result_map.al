## e2e — `Result::map` / `Result::map_err` (Stdlib §160): the functorial map over each arm, a
## THREE-type-parameter generic (`map(T, E, U, …)`). Exercises 3-type-param monomorphization
## (substitute/mangle/erase THREE type-args: `…__map__u64__u64__u64`) + the generic-enum-return
## substitution on the result binding (`rr := map(…)` sizes/matches `Result(U, E)`). Called BARE:
## the resolver routes `map(u64,u64,u64,…)` (3 leading type-args) to `result::map`/ntpc-3 over the
## same-arity `alloc::vec::map`/ntpc-2 by matching the spelled type-arg count. The `alloc::vec`
## reference triggers base-prelude injection.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

inc := fn(x : u64) -> u64 { return x + 1 }

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r0 := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r0))
  mut ar := arena_over(bp, 65536)
  mut v := alloc::vec::new(u64, ptr(ar))          ## triggers base-prelude injection
  alloc::vec::push(u64, v, 1).expect("p")

  mut r : u64 = 0

  ## Result::map — Ok(19) → Ok(20) (maps the Ok arm)
  rm := map(u64, u64, u64, Result(u64, u64).Ok(19), inc)
  match rm { Result::Ok(x) => { r = r + x } Result::Err(e) => { r = r + 500 } }

  ## Result::map — Err(_) stays Err, value unchanged (f not applied)
  rme := map(u64, u64, u64, Result(u64, u64).Err(7), inc)
  match rme { Result::Ok(x) => { r = r + 500 } Result::Err(e) => { r = r + e } }

  ## Result::map_err — Err(14) → Err(15) (maps the Err arm)
  re := map_err(u64, u64, u64, Result(u64, u64).Err(14), inc)
  match re { Result::Ok(x) => { r = r + 500 } Result::Err(e) => { r = r + e } }

  ## r = 20 + 7 + 15 = 42
  if r == 42 { return 42 }
  1
}
