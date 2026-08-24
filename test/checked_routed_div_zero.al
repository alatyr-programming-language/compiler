## CG-13 / Concurrency §6.1: a checked routed scalar `/` must trap through the same direct inline
## mechanism as checked overflow. `std::io` injects `base::num`, so the division below expands the
## shipped routed operator body; its former `panic("division by zero")` is not an allowed mechanism.
## The zero arrives through a runtime function parameter, keeping the operation-site guard live.
divide := fn(a : u64, b : u64) -> u64 { return a / b }
main := fn() -> u64 {
  z := std::io::print("")
  return divide(42, u64(z))
}
