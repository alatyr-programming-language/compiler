## CLAYOUT S3(b) — `deref(p)` where `p` points at a §7 VIEW, in the three shapes the containers
## reach an element through. Types §7: a `[T]`/`str` binding, field, parameter, return value or array
## element holds the two-word `{ptr, len}` PAIR itself, so a `deref` of a pointer to one must move
## BOTH words — on the READ, on the STORE, and when the value is passed as an ARGUMENT.
##
## The pointee type is recovered from the pointer's origin. Measured before this stage, with the pair
## written through each pointer and read straight back:
##   * a NON-generic helper `-> ptr(mut str)`:      `deref(at_s(base, 0)).len` = 0, `io::print` empty
##   * a GENERIC helper `-> ptr(mut T)` at T = str: `deref(at_p(str, base, 1)).len` = 0, print empty
##   * a pointer LOCAL bound from either:           `deref(p).len` = 0, print empty
## and the STORE through the call-derived pointer moved one word (the length word stayed 0). All
## silent wrong values (I11).
##
## The generic case is resolved by TYPE-PARAMETER POSITION: `at_p`'s return `ptr(mut T)` names its own
## parameter `T`, whose position (0) carries the call's type argument `str`. Never by name — two
## different `T`s can share a spelling.
##
## Elements of DIFFERENT lengths at DIFFERENT addresses, checked by CONTENT (`str_eq` + `bytes`), so
## neither a shared length nor a neighbouring element can pass by accident. Returns 42.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

## a NON-generic element pointer (concrete pointee `str`)
at_s := fn(base : usize, i : usize) -> ptr(mut str) {
  unchecked bitcast(ptr(mut str), base + i * 16)
}
## the GENERIC shape the stdlib containers use (`dq_elem`, `val_at`, `omap_val_elem`, `oset_elem`)
at_p := fn(T : type, base : usize, i : usize) -> ptr(mut T) {
  unchecked bitcast(ptr(mut T), base + i * size(T))
}
## read one raw machine word, to prove the STORE really wrote both words of the pair
raw := fn(base : usize, k : usize) -> u64 {
  q := unchecked bitcast(ptr(mut u64), base + k * 8)
  return deref(q)
}

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 262144, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  base := unchecked bitcast(usize, bp)

  ## STORE through a call-derived pointer (both words) — element 0 "abc", element 1 "wxyz"
  w0 := at_s(base, 0)
  deref(w0) = "abc"
  deref(at_p(str, base, 1)) = "wxyz"
  if raw(base, 1) != 3 { return 1 }
  if raw(base, 3) != 4 { return 2 }
  if raw(base, 0) == 0 { return 3 }
  if raw(base, 2) == 0 { return 4 }
  if raw(base, 0) == raw(base, 2) { return 5 }

  ## READ: `x := deref(<non-generic call>)`
  a := deref(at_s(base, 0))
  if a.len != 3 { return 6 }
  if not str_eq(a, "abc") { return 7 }

  ## READ: `x := deref(<generic call>)` — the type-parameter-position resolution
  b := deref(at_p(str, base, 1))
  if b.len != 4 { return 8 }
  if not str_eq(b, "wxyz") { return 9 }
  bb := bytes(b)
  if u64(bb[0]) != 119 { return 10 }
  if u64(bb[3]) != 122 { return 11 }

  ## READ: `x := deref(p)` where `p` is a pointer LOCAL bound from such a call
  p := at_s(base, 0)
  c := deref(p)
  if c.len != 3 { return 12 }
  if not str_eq(c, "abc") { return 13 }
  q := at_p(str, base, 1)
  d := deref(q)
  if d.len != 4 { return 14 }
  if not str_eq(d, "wxyz") { return 15 }

  ## `deref(p)` as a call ARGUMENT (the `io::print(deref(p))` shape) — the view is passed as its pair
  if base::str::byte_len(deref(at_s(base, 0))) != 3 { return 16 }
  if base::str::byte_len(deref(at_p(str, base, 1))) != 4 { return 17 }
  if not str_eq(deref(at_s(base, 0)), "abc") { return 18 }
  if not str_eq(deref(q), "wxyz") { return 19 }

  ## the store must not have disturbed its neighbour
  e := deref(at_s(base, 0))
  if not str_eq(e, "abc") { return 20 }
  return 42
}
