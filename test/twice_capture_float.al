## FN-6 §6.2 regression — a CAPTURING closure passed to a higher-order fn (`twice`) whose BODY carries
## a FLOAT LITERAL. The driver's D-cap path DEEP-CLONES `twice` into a fresh `__hoflam<fnpos>` (threading
## f's capture `c` as a trailing param). String-literal labels in the clone are renumbered, but a
## `FloatLit`'s label IS its source-span start (no separate label field), so the clone copies it VERBATIM
## → BOTH the original `twice` and the clone would emit `.Lflt<offset>:` in `.rodata` → an assembler
## "symbol already defined". `emit_rodata_expr` now DEDUPS float `.rodata` entries by source offset (one
## shared entry; both `movsd .Lflt<offset>` loads resolve to it), so the program assembles and runs.
## c := 1; twice(f, 20) = (20+1) + (20+1) = 42; the `u64(1.5)=1` bias is added then subtracted back.
twice := fn(g : u64, x : u64) -> u64 {
  half := 1.5
  return g(x) + g(x) + u64(half) - 1
}
main := fn() -> u64 {
  c := 1
  f := fn(n : u64) -> u64 { return n + c }
  return twice(f, 20)
}
