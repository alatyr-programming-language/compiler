## Explicit overflow-policy operations (Concurrency §6.3 / CG-8; appendix 160 §4.3): the prelude
## families wrapping_* / saturating_* / checked_* (-> Option) / overflowing_* (-> (T, bool)) on the
## integer interpretations, resolved via UFCS (`a.wrapping_add(b)`). Exercises the four contracts at
## the u8 and u64 boundaries plus a signed (i32) case; each assertion adds 1 to `acc`, and the program
## returns 42 iff ALL 24 hold (a failure returns the count, which is not 42). The explicit `Option(u8)`
## annotations pull the base prelude closure (num.al) into this single-file program. x86_64-only (the
## scalar numeric operators these rest on are x86_64-gated), so registered `run_x86` (sweep-excluded).
main := fn() -> u64 {
  mut acc : u64 = 0
  a255 : u8 = 255
  a200 : u8 = 200
  a100 : u8 = 100
  a20  : u8 = 20
  a10  : u8 = 10
  a5   : u8 = 5
  a3   : u8 = 3
  a0   : u8 = 0
  mx   : u64 = 18446744073709551615                          ## u64 MAX
  lo   : i32 = 0 - 2000000000
  imin : i32 = i32(0 - 2147483648)                           ## i32 MIN

  ## wrapping_* — two's-complement wrap at the type width.
  if a255.wrapping_add(1) == 0 { acc = acc + 1 }             ## 255 + 1 -> 0
  if a0.wrapping_sub(1) == 255 { acc = acc + 1 }             ## 0 - 1 -> 255
  if a200.wrapping_mul(2) == 144 { acc = acc + 1 }           ## 400 & 0xFF = 144
  if mx.wrapping_add(3) == 2 { acc = acc + 1 }               ## u64 MAX + 3 -> 2
  if mx.wrapping_mul(2) == 18446744073709551614 { acc = acc + 1 }  ## MAX*2 wraps to MAX-1

  ## saturating_* — clamp to [min, max].
  if a255.saturating_add(a10) == 255 { acc = acc + 1 }       ## clamp to u8 MAX
  if a5.saturating_sub(a10) == 0 { acc = acc + 1 }           ## clamp to u8 MIN (0)
  if a200.saturating_mul(2) == 255 { acc = acc + 1 }         ## clamp to u8 MAX
  if a100.saturating_add(a100) == 200 { acc = acc + 1 }      ## no overflow -> exact 200
  if mx.saturating_add(9) == mx { acc = acc + 1 }            ## clamp to u64 MAX
  if lo.saturating_add(lo) == imin { acc = acc + 1 }         ## i32 -4e9 clamps to MIN
  if lo.saturating_sub(2000000000) == imin { acc = acc + 1 } ## i32 -4e9 clamps to MIN

  ## checked_* — None on overflow, Some(value) when it fits.
  o1 : Option(u8) = a255.checked_add(1)
  match o1 { None => { acc = acc + 1 } Some(v) => {} }                             ## overflow -> None
  o2 : Option(u8) = a3.checked_add(4)
  match o2 { Some(v) => { if v == 7 { acc = acc + 1 } } None => {} }               ## fits -> Some(7)
  o3 : Option(u8) = a5.checked_sub(a10)
  match o3 { None => { acc = acc + 1 } Some(v) => {} }                             ## underflow -> None
  o4 : Option(u8) = a20.checked_mul(a20)
  match o4 { None => { acc = acc + 1 } Some(v) => {} }                             ## 400 > 255 -> None
  o5 : Option(u8) = a10.checked_mul(a20)
  match o5 { Some(v) => { if v == 200 { acc = acc + 1 } } None => {} }             ## 200 fits -> Some
  o6 : Option(u64) = mx.checked_add(1)
  match o6 { None => { acc = acc + 1 } Some(v) => {} }                             ## u64 MAX + 1 -> None

  ## overflowing_* — (wrapped, did-overflow).
  r1 : (u8, bool) = a255.overflowing_add(1)
  if r1.1 { acc = acc + 1 }                                  ## overflow flag set
  if r1.0 == 0 { acc = acc + 1 }                             ## wrapped value
  r2 : (u8, bool) = a3.overflowing_add(4)
  if r2.1 == false { acc = acc + 1 }                         ## no overflow
  if r2.0 == 7 { acc = acc + 1 }                             ## exact value
  rr : (u64, bool) = mx.overflowing_mul(2)
  if rr.1 { acc = acc + 1 }                                  ## u64 MAX * 2 overflows
  if rr.0 == 18446744073709551614 { acc = acc + 1 }          ## wrapped product

  if acc == 24 { return 42 }
  return acc
}
