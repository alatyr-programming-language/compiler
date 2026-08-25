## §5 fmt (Control Flow §9.3) — `defer` round-trips as SURFACE syntax. The parser desugars `defer <expr>`
## to the marker call `__defer(<expr>)` and the block form of defer to the FLAT chain `__deferblk()` → S1 → S2
## → `__deferblkend()`, all of which stay in the statement list; fmt rendered those markers LITERALLY, so
## formatting a source rewrote the user's `defer` into compiler internals (it happened to still run,
## because the lower re-intercepts the marker NAMES — idempotence and the exit code alone cannot catch
## it, hence the `fmt_test_has` needles). LIFO order is locked by the digit trace: the block registers
## LAST, so it drains FIRST — mark(1), mark(2), then mark(3) → ACC = 123.
mut ACC : u64 = 0

mark := fn(n : u64) -> u64 {
  ACC = ACC * 10 + n
  0
}

f := fn() -> u64 {
  defer mark(3)
  defer {
    mark(1)
    mark(2)
  }
  return 0
}

main := fn() -> u64 {
  z := f()
  return ACC + z
}
