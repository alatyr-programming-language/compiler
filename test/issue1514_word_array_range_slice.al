## #1514 / #1559 — a range slice over a fixed array whose element is narrower than a word.
##
## Types §6.4 lays `[T; N]` out contiguously at `T`'s size rounded up to its alignment, and a
## `Slice(T)` over it reads element `i` at `ptr + i × stride`. So every check below holds, on every
## backend. x86_64 keeps these arrays one WORD per element (the word array ABI; only an annotated
## `[u8|i8|bits8; N]` local is packed), and its range-slice producers handed out a view over those
## word-spaced elements: any consumer that follows §6.4 (a `Slice(T)` parameter, an annotated `for`)
## read the wrong bytes. Until the arrays are packed (#1559), x86_64 refuses the range slice over a
## `u16|i16` or inferred `u8|i8` array at its source line instead of answering wrong. The `[u32; N]`
## check (4) and the `[bool; N]` check (6) are NOT refused (PR #1564's decisions keep the existing
## programs over those arrays building): on x86_64 they are silent wrong values tracked by #1559, and
## this fixture still stops at check 1's range.
##
## Each check owns a code from 1 up; 42 means all held.
##
## Parent `5a2426cc` (x86_64, omen): built rc 0, ran to 1 where 42 was due — the annotated `for` over
## `a16[0..3]` read 1000, then the zero high bytes of element 0.
pass16 := fn(s : Slice(u16)) -> Slice(u16) { s }
pass32 := fn(s : Slice(u32)) -> Slice(u32) { s }
pass8 := fn(s : Slice(u8)) -> Slice(u8) { s }
sumb := fn(s : Slice(bool)) -> u64 {
  mut n : u64 = 0
  for x in s {
    if x { n = n * 10 + 1 } else { n = n * 10 + 2 }
  }
  n
}

main := fn() -> u64 {
  ## the issue's own program: an annotated view, iterated
  a16 : [u16; 3] = [1000, 2000, 3000]
  mut n16 : u64 = 0
  s : Slice(u16) = a16[0..3]
  for x in s { n16 = n16 * 10 + u64(x) }
  if n16 != 1000 * 100 + 2000 * 10 + 3000 { return 1 }

  ## through a `Slice(u16)` parameter, indexed and iterated
  r16 := pass16(a16[0..3])
  if u64(r16[2]) != 3000 { return 2 }
  mut m16 : u64 = 0
  for x in pass16(a16[1..3]) { m16 = m16 + u64(x) }
  if m16 != 5000 { return 3 }

  ## a `[u32; N]` view starting past element 0
  a32 : [u32; 3] = [7, 8, 9]
  r32 := pass32(a32[1..3])
  if u64(r32[0]) != 8 or u64(r32[1]) != 9 { return 4 }

  ## an INFERRED `[u8; N]` (no annotation, so not the packed byte tier)
  t := [u8(1), u8(200), u8(3)]
  q := pass8(t[0..3])
  mut k : u64 = 0
  for x in q { k = k + u64(x) }
  if k != 204 { return 5 }

  ## a `[bool; N]`, one byte per element in a `Slice(bool)`
  fl : [bool; 3] = [true, false, true]
  if sumb(fl[0..3]) != 121 { return 6 }
  42
}
## expect: run 42
