## A bare `str` module GLOBAL: its {ptr, len} must be emitted as two .data words
## (word 0 = rodata-bytes address, word 1 = byte length) and READ from the .data
## label (not a frame slot). Was a Priority-1 silent miscompile: `.len` read 0 and
## `bytes(S)[i]` segfaulted (null-ptr deref). Returns 42 iff both words are right.
mut S := "hello!!"

main := fn() -> u64 {
  ## word 1 (len) must be 7
  if S.len != 7 { return 1 }
  ## word 0 (ptr) must point at the rodata bytes: 'h'=104, 'e'=101, '!'=33
  if bytes(S)[0] != 104 { return 2 }
  if bytes(S)[1] != 101 { return 3 }
  if bytes(S)[6] != 33 { return 4 }
  return 42
}
