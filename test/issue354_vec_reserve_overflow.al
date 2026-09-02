## e2e / issue #354 — `alloc::vec::reserve` is declared fallible (Stdlib appendix §6: `Vec` v1
## carries `reserve(n)`, and a fallible operation returns `Result`, an allocation failure surfacing
## as `AllocError`, §5.1), so a request it cannot represent in `usize` must come back as an error
## VALUE — not as a trap, and not as a silently satisfied no-op. Three size steps inside `reserve`
## can leave `usize`: the requested count `len + additional`, the capacity doubling, and the byte
## size `new_cap * size(T)` handed to `allocate`. On the parent each of them was a bare checked
## operator, so every row below aborted the process (SIGILL, exit 132) before `allocate` was
## reached; codes 107, 108, 109 and 115 each single one of them out.
##
## The ordinary rows matter as much as the error rows: a no-op reserve and an ordinary growth must
## keep succeeding, a representable-but-unfittable request must keep its own `OutOfMemory` variant,
## and the vector must be intact and still growable after a rejected request. Each check owns a
## distinct code from 100 up; 42 means every one of them held.
##
## Elements are `u64`: `try_at` at `T = u8` delivers an `Option(u8)` whose payload compares unequal
## to its own value outside the callee, which is an independent defect and would confound the rows
## here.
vec := alloc::vec
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

## `Ok(want)` exactly — an `Err` arm, or a different reported capacity, is a miss.
ok_is := fn(r : Result(usize, AllocError), want : usize) -> bool {
  match r {
    Result::Ok(n) => { n == want }
    Result::Err(e) => { false }
  }
}

## `Err(AllocError.SizeTooLarge)` exactly. `OutOfMemory` and `BadAlignment` are misses, so a fix
## that folded every growth failure into one variant would not pass.
is_too_large := fn(r : Result(usize, AllocError)) -> bool {
  match r {
    Result::Ok(n) => { false }
    Result::Err(e) => {
      match e {
        AllocError.SizeTooLarge => { true }
        _ => { false }
      }
    }
  }
}

## `Err(AllocError.OutOfMemory)` exactly — a request that fits in `usize` and merely does not fit
## the arena must not be reclassified as an overflow.
is_oom := fn(r : Result(usize, AllocError)) -> bool {
  match r {
    Result::Ok(n) => { false }
    Result::Err(e) => {
      match e {
        AllocError.OutOfMemory => { true }
        _ => { false }
      }
    }
  }
}

elem_is := fn(o : Option(u64), want : u64) -> bool {
  match o {
    Option::Some(x) => { x == want }
    Option::None => { false }
  }
}

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  m := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, m))
  mut ar := arena_over(bp, 65536)

  ## len 2, cap 4. 11 and 22 are distinguishable and are not neighbours, so a copy that shifted or
  ## duplicated an element during a growth would show.
  mut v := vec::with_capacity(u64, ptr(ar), 4)
  vec::push(u64, v, 11).expect("push 0")
  vec::push(u64, v, 22).expect("push 1")

  ## --- the rows that must NOT start failing -----------------------------------
  ## need == cap exactly: the no-op arm, reporting the unchanged capacity.
  if not ok_is(vec::reserve(u64, v, 2), 4) { return 100 }
  ## need < cap: still a no-op.
  if not ok_is(vec::reserve(u64, v, 0), 4) { return 101 }
  ## An ordinary growth: need 7 > cap 4, so the doubling lands on 8.
  if not ok_is(vec::reserve(u64, v, 5), 8) { return 102 }
  if vec::capacity(u64, ptr(v)) != 8 { return 103 }
  if vec::vlen(u64, ptr(v)) != 2 { return 104 }
  if not elem_is(vec::try_at(u64, ptr(v), 0), 11) { return 105 }
  if not elem_is(vec::try_at(u64, ptr(v), 1), 22) { return 106 }

  ## --- the boundary of `len + additional` -------------------------------------
  ## 2 + (usize::MAX - 2) == usize::MAX exactly: the count is representable, so the count check
  ## must let it through and the refusal has to come from the capacity doubling instead — 4 * 2^k
  ## never reaches usize::MAX, so the doubling is what runs out of `usize`.
  if not is_too_large(vec::reserve(u64, v, 18446744073709551613)) { return 107 }
  ## One past that boundary: 2 + (usize::MAX - 1) wraps to 0. A wrapped sum is always BELOW `len`,
  ## hence always at or below `cap`, so unguarded wrapping arithmetic reports the WRONG VALUE
  ## `Ok(8)` — a request for more than the address space answered as already satisfied. That is
  ## why the count step needs its own test and not just a non-trapping operator.
  if not is_too_large(vec::reserve(u64, v, 18446744073709551614)) { return 108 }
  ## Further past it: 2 + usize::MAX wraps to 1, also at or below cap.
  if not is_too_large(vec::reserve(u64, v, 18446744073709551615)) { return 109 }

  ## The vector survives a refused request untouched and still grows afterwards.
  if vec::capacity(u64, ptr(v)) != 8 { return 110 }
  if vec::vlen(u64, ptr(v)) != 2 { return 111 }
  if not elem_is(vec::try_at(u64, ptr(v), 0), 11) { return 112 }
  if not ok_is(vec::reserve(u64, v, 20), 32) { return 113 }
  if not elem_is(vec::try_at(u64, ptr(v), 1), 22) { return 114 }

  ## --- the byte-size step on its own ------------------------------------------
  ## cap 1 doubles to 2^63 to cover 2^62 + 1 elements. Both the count and the doubled capacity are
  ## representable, so this row reaches the `new_cap * size(T)` step and only that step: 2^63 * 8
  ## bytes is not a `usize`. Left unguarded it would hand `allocate` a wrapped byte count of 0.
  mut w := vec::with_capacity(u64, ptr(ar), 1)
  if not is_too_large(vec::reserve(u64, w, 4611686018427387905)) { return 115 }

  ## --- a representable request that simply does not fit -----------------------
  ## A 64-byte arena, 8 of them already taken: the grown byte size (128 * 8) is a perfectly good
  ## `usize` and merely exceeds the remaining capacity, so this stays `OutOfMemory`.
  sp := unchecked bitcast(ptr(mut bits8), bitcast(usize, bp) + 32768)
  mut small := arena_over(sp, 64)
  mut t := vec::with_capacity(u64, ptr(small), 1)
  if not is_oom(vec::reserve(u64, t, 100)) { return 116 }

  vec::free(u64, t)
  vec::free(u64, w)
  vec::free(u64, v)
  return 42
}
