## Issue #580, closed-set witness — BIT 4, an INTRINSIC namespace.
##
## `atomic` (Concurrency §2) and the `volatile` MMIO pair beside it are matched by the lowerer on
## the WHOLE callee string, so their heads never reach a declaration scan at all — which is exactly
## why the naive "is the head a module?" arm refused all ten atomic sites. This is the only arm of
## the closed set that needs a literal list, and that list is a transcription of the specification.
## Kind mask exactly 16.
main := fn() -> u64 {
  mut cell : u64 = 0
  atomic::store(ptr(cell), 60, Ordering.release)
  v := atomic::load(ptr(cell), Ordering.acquire)
  w := volatile::load(ptr(cell))
  v + w - 54
}
