## e2e — `Option::map` (Stdlib §160): the functorial `map` over a fn value, previously deferred on
## the generic-enum-return-substitution gap. Each `xm := map(…)` binds a generic call returning
## `Option(U)` where `U` is `map`'s OWN type-param; the caller sizes/stages/matches the result with
## `U` resolved to the call's type-arg (the substitution on the result binding). The cross-module
## same-name `map` (Option/4 vs Vec/5) routes by arity. Base-tier prelude; the `alloc::vec` reference
## triggers base-prelude injection. (Struct `U` from a struct LOCAL works — see ambient_hashmap_value;
## a struct `U` produced by the fn value `Some(f(v))` and `Result::map`/3-type-params stay deferred.)
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

dbl := fn(x : u64) -> u64 { return x + x }

Pt := struct { x : u64, y : u64 }
mkpt := fn(v : u64) -> Pt { return Pt(x = v, y = 2) }

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r0 := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r0))
  mut ar := arena_over(bp, 65536)
  mut v := alloc::vec::new(u64, ptr(ar))          ## triggers base-prelude injection
  alloc::vec::push(u64, v, 1).expect("p")

  mut r : u64 = 0

  ## Option::map — Some(10) → Some(20)
  om := map(u64, u64, Option(u64).Some(10), dbl)
  match om { Option::Some(x) => { r = r + x } Option::None => { r = r + 500 } }

  ## Option::map — Some(10) → Some(20)
  om2 := map(u64, u64, Option(u64).Some(10), dbl)
  match om2 { Option::Some(x) => { r = r + x } Option::None => { r = r + 500 } }

  ## Option::map — None stays None
  on := map(u64, u64, Option(u64).None, dbl)
  match on { Option::Some(x) => { r = r + 500 } Option::None => { r = r + 0 } }

  ## Option::map producing a STRUCT via the fn value — Some(0) → Some(Pt{0,2}); read both fields.
  ## Exercises `Some(f(v))` where the fn value returns a struct (the payload-call struct staging).
  op := map(u64, Pt, Option(u64).Some(0), mkpt)
  match op { Option::Some(p) => { r = r + p.x + p.y } Option::None => { r = r + 500 } }

  ## r = 20 + 20 + 0 + (0+2) = 42
  if r == 42 { return 42 }
  1
}
