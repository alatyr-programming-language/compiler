## #1514 / #1622 — a range slice over a fixed array whose element is narrower than a word, passed to,
## returned from, indexed and iterated through `Slice(T)` parameters and results.
##
## Types §6.4 lays `[T; N]` out contiguously at `T`'s size rounded up to its alignment, and a `Slice(T)`
## over it reads element `i` at `ptr + i × stride`; Types §7 makes the view the two-word pair, `ptr` at
## byte 0 and `len` at byte 8 (Stdlib appendix §3.5). So every check below holds, on every backend.
## The shared IR builds all of it (#1622): view parameters (the address of a caller-owned copy of the
## pair), view results (the pair's two words), `for` over a view, and a range over an annotated or an
## inferred scalar array local, at the element's own stride.
##
## Each check owns a code from 1 up; 42 means all held.
##
## Parent `9e60e8aa` (omen): x86_64 built every function with the legacy emitter, whose arrays keep one
## WORD per element while its `Slice(T)` readers step `T`'s own size, and answered 1 (check 1 read 1000,
## then element 0's zero high bytes). aarch64 and riscv64 exited 133 and wasm 134. The register twins and
## wasm still leave this program to legacy (their legacy emitters step a narrow view by the word and
## return a view's address, `ir::sig_has_narrow_view` / `ir::ret_is_view`), where the slice argument is
## a fail-loud stub: known deviations under #1288.
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
