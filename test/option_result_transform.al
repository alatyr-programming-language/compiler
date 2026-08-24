## e2e — `Option`/`Result` transform methods (Stdlib §160): `Option::and_then`, `Option::ok_or`,
## `Result::ok`. Each converts one generic enum to another (scalar payloads), returned from a
## generic call and matched; `and_then` takes a monomorphized fn value. Base-tier prelude, called
## bare with explicit type-args (like `slice::find`); the `alloc::vec` reference triggers the
## base-prelude injection. Sum lands on 42. (`map` is deferred — an open overload/fn-value gap.)
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

inc_opt := fn(x : u64) -> Option(u64) { return Option(u64).Some(x + 1) }

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r0 := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r0))
  mut ar := arena_over(bp, 65536)
  mut v := alloc::vec::new(u64, ptr(ar))          ## triggers base-prelude injection
  alloc::vec::push(u64, v, 1).expect("p")

  mut r : u64 = 0

  ## Option::and_then — Some(3) → f(3) = Some(4)
  oa := and_then(u64, u64, Option(u64).Some(3), inc_opt)
  match oa { Option::Some(x) => { r = r + x } Option::None => { r = r + 500 } }

  ## Result::ok — Ok(20) → Some(20); Err(_) → None
  oo := ok(u64, u64, Result(u64, u64).Ok(20))
  match oo { Option::Some(x) => { r = r + x } Option::None => { r = r + 500 } }
  oe := ok(u64, u64, Result(u64, u64).Err(9))
  match oe { Option::Some(x) => { r = r + 500 } Option::None => { r = r + 0 } }

  ## Option::ok_or — Some(18) → Ok(18)
  rr := ok_or(u64, u64, Option(u64).Some(18), 999)
  match rr { Result::Ok(x) => { r = r + x } Result::Err(e) => { r = r + 500 } }

  ## r = 4 + 20 + 0 + 18 = 42
  if r == 42 { return 42 }
  1
}
