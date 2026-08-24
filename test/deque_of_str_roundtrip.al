## CLAYOUT S3(b) — a `Deque(str)` must round-trip its elements, VALUES included.
##
## `alloc::deque` reaches an element through the helper `dq_elem(T, d, i) -> ptr(mut T)`. At the use
## site (`deref(dq_elem(…))` / `slot := dq_elem(…)` then `deref(slot) = x`) the POINTEE type was not
## recoverable, so the two-word §7 `{ptr, len}` view was never materialized: the store moved ONE word
## and the read fell through to an EMPTY pair. Measured before this stage on the shipped stdlib:
## `dq_at(d, 0).len` = 0, `dq_at(d, 1).len` = 0, `front(d).len` = 0 — for elements "abc"/"wxyz"/"hi".
## Silent wrong values, the forbidden outcome (I11).
##
## The fix resolves the callee's returned pointee by TYPE-PARAMETER POSITION through the call's type
## argument (never by name — two different `T`s can share a spelling). This checks CONTENT, not just
## a length, with elements of THREE DIFFERENT lengths so a shared/stale length cannot pass by
## coincidence, and exercises every public read surface (`dq_at`, `front`, `back`, `pop_front`).
## Returns 42.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 262144, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 262144)

  mut d := alloc::deque::deque(str, ptr(ar), 8)
  alloc::deque::push_back(str, d, "abc").expect("push_back")
  alloc::deque::push_back(str, d, "wxyz").expect("push_back")
  alloc::deque::push_front(str, d, "hi").expect("push_front")
  if alloc::deque::dq_len(str, ptr(d)) != 3 { return 1 }

  ## logical order is now hi, abc, wxyz — three DIFFERENT lengths
  o0 := alloc::deque::dq_at(str, ptr(d), 0)
  match o0 {
    Option::Some(t) => {
      if t.len != 2 { return 2 }
      if not str_eq(t, "hi") { return 3 }
    }
    Option::None => { return 4 }
  }
  o1 := alloc::deque::dq_at(str, ptr(d), 1)
  match o1 {
    Option::Some(t) => {
      if t.len != 3 { return 5 }
      if not str_eq(t, "abc") { return 6 }
    }
    Option::None => { return 7 }
  }
  o2 := alloc::deque::dq_at(str, ptr(d), 2)
  match o2 {
    Option::Some(t) => {
      if t.len != 4 { return 8 }
      if not str_eq(t, "wxyz") { return 9 }
      ## byte-level: the pointer really addresses this element's own bytes, not a neighbour's
      b2 := bytes(t)
      if u64(b2[0]) != 119 { return 10 }
      if u64(b2[3]) != 122 { return 11 }
    }
    Option::None => { return 12 }
  }

  f := alloc::deque::front(str, ptr(d))
  match f {
    Option::Some(t) => { if not str_eq(t, "hi") { return 13 } }
    Option::None => { return 14 }
  }
  bk := alloc::deque::back(str, ptr(d))
  match bk {
    Option::Some(t) => { if not str_eq(t, "wxyz") { return 15 } }
    Option::None => { return 16 }
  }

  pf := alloc::deque::pop_front(str, d)
  match pf {
    Option::Some(t) => {
      if t.len != 2 { return 17 }
      if not str_eq(t, "hi") { return 18 }
    }
    Option::None => { return 19 }
  }
  if alloc::deque::dq_len(str, ptr(d)) != 2 { return 20 }
  a0 := alloc::deque::dq_at(str, ptr(d), 0)
  match a0 {
    Option::Some(t) => { if not str_eq(t, "abc") { return 21 } }
    Option::None => { return 22 }
  }
  return 42
}
