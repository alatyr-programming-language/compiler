## REGALLOC COMMIT 6 — TWO barriers, TWO live-across scalars. `readf` is register-allocated (by-ref struct
## param `p`); `p.a` and `p.b` are each a BARRIER (text emit_gas). `t1` is live across barrier 1 (used by
## `t2` after it) and `t2` is live across barrier 2 — BOTH are forced to distinct spill slots by the
## barriers' full clobber, and both must stay disjoint from `p`'s frame slot. t1=10+5=15; y1=p.a=12;
## t2=15+12=27; y2=p.b=15; 27+15 = 42. Same under default and ALATYR_RA=0.
Pair := struct { a : u64, b : u64 }
readf := fn(p : Pair, k : u64) -> u64 {
  t1 := k + 5
  y1 := p.a
  t2 := t1 + y1
  y2 := p.b
  t2 + y2
}
main := fn() -> u64 {
  q := Pair(a = 12, b = 15)
  readf(q, 10)
}
