## REGALLOC COMMIT 6 — the BARRIER bracket. `readf` matches the WIDENED scalar-leaf shape: it has a by-ref
## STRUCT param `p` (all-scalar fields), so it is register-allocated, but the scalar field read `p.b` is a
## construct the IR does NOT model — it is emitted through the TEXT emitter (`emit_gas`) at render time,
## bracketed by a FULL register clobber. `t` is computed BEFORE the barrier and used AFTER it, so it is
## LIVE ACROSS the barrier: the clobber forces `t` to a spill slot (no register survives the opaque text
## snippet) that must be DISJOINT from `p`'s frame slot — the scalar↔slot bridge. 10+20 + p.b(=12) = 42, a
## UNIQUE correct answer; a lost/aliased scalar returns something else. Same under default (regalloc+barrier)
## and ALATYR_RA=0 (pure text path).
Pair := struct { a : u64, b : u64 }
readf := fn(p : Pair, k : u64) -> u64 {
  t := k + 20
  y := p.b
  t + y
}
main := fn() -> u64 {
  q := Pair(a = 100, b = 12)
  readf(q, 10)
}
