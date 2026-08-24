## fmt fixture — the `unchecked` surface (Types §4.2 scoped verification mode, D70/D82). Two wrong
## renders, both silent:
##   • `unchecked` is a `p_factor` PREFIX, binding tighter than every binary operator, so the scope
##     body needs grouping. `b := unchecked { lo - hi }` came back as `unchecked lo - hi`, which
##     re-parses as `(unchecked lo) - hi` — the subtraction is back inside CHECKED mode and the
##     underflow traps (SIGILL 132) instead of wrapping.
##   • `unchecked bitcast(ptr(T), v)` parses as `Unchecked(Bitcast(…))` and the `Bitcast` arm re-emits
##     the whole `unchecked bitcast(…)` surface itself, so the keyword was emitted TWICE — and the
##     stored type span is the pointee for `ptr(u8)` but the WHOLE type for `ptr(mut Pt)`, which the
##     unconditional `ptr(` wrapper turned into `ptr(ptr(mut Pt))`. Both grew by one level per pass:
##     fmt was not idempotent, and the second render was a different TYPE.
## Returns 42.
Pt := struct { a : u64, b : u64 }

main := fn() -> u64 {
  mut lo : u64 = 5
  mut hi : u64 = 7
  d := unchecked { lo - hi }
  e := unchecked { d + hi }
  if e != lo { return 1 }
  base := 4096
  p : ptr(mut Pt) = unchecked bitcast(ptr(mut Pt), base)
  q : ptr(u8) = unchecked bitcast(ptr(u8), base)
  r : ptr(mut u64) = unchecked bitcast(ptr(mut u64), base)
  return 42
}
