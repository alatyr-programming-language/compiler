## e2e / issue #355 — `alloc::string`'s `push` and `push_str` report the **new byte length**, not the
## number of bytes they appended. The pinned Stdlib appendix §6 fixes the success type: because the
## language has no unit type, "a fallible mutator with no natural result carries a `usize` count in
## its `Ok` arm — the new length for `push`/`push_str`". Both wrappers forwarded `alloc::strbuf`
## straight through, and `strbuf`'s writers report what they WROTE (`bs.len` for `push_str`, the
## UTF-8 encoding width for `push_char`), which is the buffer-writer convention and not `String`'s.
##
## The two conventions coincide for the very first append into an empty string, which is exactly why
## a one-append fixture proves nothing here: the rows below append repeatedly and each one owns a
## distinct code from 100 up. On the parent, row 104 is the first divergence — `push(char(65))` into
## a 2-byte string answered `Ok(1)` where the specified new length is 3.
##
## Widths covered: a 2-byte `str`, a 1-byte ASCII `char`, a 1-byte `str`, an EMPTY `str` (which must
## report the length UNCHANGED, not 0), and the 2-, 3- and 4-byte UTF-8 `char` encodings. The final
## length must equal 2+1+1+0+2+3+4 = 13, so the accumulated report and the buffer agree. A second
## string re-runs the sequence ACROSS a reallocation (capacity 1), and a third checks that a `char`
## is a valid FIRST append into an empty string.
##
## The buffer length is read as the `.len` FIELD (as `ambient_string` does) rather than through
## `alloc::string::len`, which is unreachable from a program: the bare `len` name resolves against
## the generic `base::slice::len(T, s)` / `alloc::vec::len(T, v)` overloads and the call is refused
## for a missing comptime type argument. That is an independent defect of the accessor surface #353
## is about (the spec's name for this read is `byte_len`), not of the result value measured here.
strm := alloc::string
ch := base::char
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

## `Ok(want)` exactly — an `Err` arm, or any other reported count, is a miss.
ok_is := fn(r : Result(usize, AllocError), want : usize) -> bool {
  match r {
    Result::Ok(n) => { n == want }
    Result::Err(e) => { false }
  }
}

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  m := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, m))
  mut ar := arena_over(bp, 65536)

  ## --- the accumulating sequence, all inside one capacity (`new` reserves 16) ----
  mut s := strm::new(ptr(ar))
  if s.len != 0 { return 100 }
  if not strm::is_empty(ptr(s)) { return 101 }

  ## The FIRST append: appended count and new length are both 2, so this row holds on the parent
  ## too. It is the control that says the fix did not simply change the value to something else.
  if not ok_is(strm::push_str(s, "hi"), 2) { return 102 }
  if s.len != 2 { return 103 }

  ## A 1-byte ASCII `char` onto 2 bytes: the specified answer is 3. The parent reported the
  ## encoding width 1 — a length that is smaller than the string was before the call.
  if not ok_is(strm::push(s, char(65)), 3) { return 104 }
  if s.len != 3 { return 105 }

  ## A 1-byte `str` onto 3 bytes: 4, where the parent reported 1.
  if not ok_is(strm::push_str(s, "!"), 4) { return 106 }

  ## The EMPTY append: nothing is written, so the length is unchanged and must be reported as 4.
  ## The parent reported 0, which reads as "the string is now empty" — the most misleading value of
  ## the old convention, and the one an `if n == 0` caller would act on.
  if not ok_is(strm::push_str(s, ""), 4) { return 107 }
  if s.len != 4 { return 108 }

  ## The multi-byte `char` encodings, each adding its own width to a non-empty string.
  ## U+00E9 é — 2 bytes: 4 + 2 = 6 (parent: 2).
  if not ok_is(strm::push(s, char(233)), 6) { return 109 }
  ## U+20AC € — 3 bytes: 6 + 3 = 9 (parent: 3).
  if not ok_is(strm::push(s, char(8364)), 9) { return 110 }
  ## U+1F600 😀 — 4 bytes: 9 + 4 = 13 (parent: 4).
  if not ok_is(strm::push(s, char(128512)), 13) { return 111 }

  ## The buffer agrees with the last reported length, and so does the borrowed `str` view: the
  ## accumulated report is the real byte length, not a coincidence of the last width.
  if s.len != 13 { return 112 }
  if strm::as_str(ptr(s)).len != 13 { return 113 }

  ## The bytes actually landed where the lengths claim. 'h' (104) at 0, 'A' (65) at 2 and '!' (33)
  ## at 3 are distinguishable and non-adjacent values, so a shifted or duplicated append would show
  ## even though every length row passed.
  b := strm::as_bytes(ptr(s))
  if b[0] != 104 { return 114 }
  if b[2] != 65 { return 115 }
  if b[3] != 33 { return 116 }

  ## --- the same reports ACROSS a reallocation -----------------------------------
  ## Capacity 1, so the second append has to grow the region. The reported length must be the
  ## post-growth byte length, not the copied-in count.
  mut g := strm::with_capacity(ptr(ar), 1)
  if not ok_is(strm::push_str(g, "abcd"), 4) { return 117 }
  if not ok_is(strm::push_str(g, "efghijkl"), 12) { return 118 }
  if not ok_is(strm::push(g, char(233)), 14) { return 119 }
  if g.len != 14 { return 120 }

  ## --- a `char` as the FIRST append into an empty string ------------------------
  ## Here the two conventions coincide again (3 bytes written into an empty string is length 3), so
  ## this row guards the fix against reporting the length of the WRONG buffer or an off-by-one.
  mut e := strm::with_capacity(ptr(ar), 1)
  if not ok_is(strm::push(e, char(8364)), 3) { return 121 }
  if e.len != 3 { return 122 }
  if strm::is_empty(ptr(e)) { return 123 }

  ## `base::char` folding is unrelated to the lengths above; the alias is used so the injected
  ## module is exercised rather than merely named.
  if u32(ch::to_upper(char(97))) != 65 { return 124 }

  strm::free(e)
  strm::free(g)
  strm::free(s)
  return 42
}
