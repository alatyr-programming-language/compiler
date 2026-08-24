## REGALLOC 6d — an inline SCALAR ARRAY LOCAL iterated with `for x in ys`. `suml` matches the
## scalar-leaf shape: an inline `[u64; 4]` array local (`ys`) whose array-literal init is emitted
## through the TEXT statement emitter (a STATEMENT BARRIER — a full register clobber), while the array
## stays FRAME-RESIDENT (its N words reserved at the frame top, RA spill slots below, no aliasing). The
## loop iterates the array with a register-allocated cursor: the accumulator `s` and the loop index stay
## in REGISTERS across the loop (no per-iteration `-N(%rbp)` reload), the element base is materialized
## with a `leaq` (LEA-SLOT) and each element read through an indexed `movq (%r..)`. 10+20+3+9 = 42, a
## UNIQUE correct answer. Same exit under default (regalloc) and ALATYR_RA=0 (pure text path).
suml := fn() -> u64 {
  ys : [u64; 4] = [10, 20, 3, 9]
  mut s : u64 = 0
  unchecked { for x in ys { s = s + x } }
  s
}
main := fn() -> u64 { suml() }
