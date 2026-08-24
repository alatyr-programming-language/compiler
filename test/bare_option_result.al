## e2e — bare `Option`/`Result` in a SINGLE-FILE program (no `alloc::`/`std::`/`@alloc` trigger) now
## forces the base prelude, so the stdlib sum types are usable standalone. Some(40) + Ok(2) = 42.
main := fn() -> u64 {
  o : Option(u64) = Option.Some(40)
  r : Result(u64, u64) = Result.Ok(2)
  mut a : u64 = 0
  match o { Option::Some(v) => { a = v } Option::None => { a = 0 } }
  mut b : u64 = 0
  match r { Result::Ok(v) => { b = v } Result::Err(e) => { b = 0 } }
  return a + b
}
