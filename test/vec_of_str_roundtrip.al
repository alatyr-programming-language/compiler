## P1-CLAYOUT S1 — a `Vec(str)` must round-trip its elements, VALUES included.
##
## `lib/alloc/vec.al` strides its backing by `size(T)`. With `size(str) == 8` (the pointer alone,
## contradicting the 16 bytes a `str` FIELD already occupied) the two-word {ptr, len} view did not fit
## its slot; the element store moved ONE word — and for the by-ref `x : T` parameter at `T = str`,
## whose slot holds a POINTER to the caller's pair, that one word was a STACK ADDRESS — while the
## element read fell through to an empty pair. Measured before this stage: `at(v, 0).len` = 0 and
## `get(v, 0)` = `Some` with len 32 or 64. Both are SILENT WRONG VALUES, the forbidden outcome.
##
## This checks the CONTENT (`bytes(...)` and `str_eq`), not merely the absence of a crash, and it
## exercises all three public read surfaces — `at` (the indexing read), `get` (the fallible read) and
## `split` (the audit's original repro, `alloc::vec::split` over a comma-separated str). Elements of
## DIFFERENT lengths are used so a stale/shared length cannot pass by coincidence. Returns 42.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 262144, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 262144)

  mut v := alloc::vec::with_capacity(str, ptr(ar), 8)
  alloc::vec::push(str, v, "abc").expect("push")
  alloc::vec::push(str, v, "wxyz").expect("push")
  alloc::vec::push(str, v, "hi").expect("push")
  if alloc::vec::len(str, ptr(v)) != 3 { return 1 }

  a0 := alloc::vec::at(str, ptr(v), 0)
  a1 := alloc::vec::at(str, ptr(v), 1)
  a2 := alloc::vec::at(str, ptr(v), 2)
  if a0.len != 3 { return 2 }
  if a1.len != 4 { return 3 }
  if a2.len != 2 { return 4 }
  if not str_eq(a0, "abc") { return 5 }
  if not str_eq(a1, "wxyz") { return 6 }
  if not str_eq(a2, "hi") { return 7 }
  ## byte-level: the pointer really points at the element's own bytes, not a neighbour's.
  b1 := bytes(a1)
  if u64(b1[0]) != 119 { return 8 }
  if u64(b1[3]) != 122 { return 9 }

  g1 := alloc::vec::get(str, ptr(v), 1)
  match g1 {
    Option::Some(t) => {
      if t.len != 4 { return 10 }
      if not str_eq(t, "wxyz") { return 11 }
    }
    Option::None => { return 12 }
  }

  mut sp := alloc::vec::split(ptr(ar), "aa,bbb,c", 44)
  if alloc::vec::len(str, ptr(sp)) != 3 { return 13 }
  s0 := alloc::vec::at(str, ptr(sp), 0)
  s1 := alloc::vec::at(str, ptr(sp), 1)
  s2 := alloc::vec::at(str, ptr(sp), 2)
  if not str_eq(s0, "aa") { return 14 }
  if not str_eq(s1, "bbb") { return 15 }
  if not str_eq(s2, "c") { return 16 }
  return 42
}
