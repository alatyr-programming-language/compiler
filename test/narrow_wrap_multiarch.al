## §4 value model on ALL FOUR backends: `unchecked` narrow-width `+`/`-`/`*` WRAPS at the type width —
## `uN` modulo 2^N, `iN` to the signed range — instead of computing in a full 64-bit register. Exit
## codes are mod-256, so the raw wrap can hide; each result is DIVIDED to lift its value clear of what
## the un-wrapped 64-bit computation would leave. This is a PLAIN `run` (the sweeps exercise a64/rv64/
## wasm too): before the non-x86 wrap it FAILED here (the backends computed in 64 bits, so `s`/`p`/`d`
## held 300 / 20000 / -100 and the divisions lifted the wrong values); after, all four agree on 54.
##   a+b = 300 & 0xFF = 44   → 44 / 4  = 11   (un-wrapped 300  / 4  = 75)
##   a*b = 20000 & 0xFF = 32 → 32 / 8  = 4    (un-wrapped 20000/ 8  = 2500)
##   b-a = -100 as u8 = 156  → 156 / 4 = 39   (un-wrapped -100 as u64 is huge)
##   11 + 4 + 39 = 54
main := fn() -> u64 {
  a : u8 = 200
  b : u8 = 100
  s := unchecked { a + b }
  p := unchecked { a * b }
  d := unchecked { b - a }
  s / 4 + p / 8 + d / 4
}
