## e2e (reject) — 2^64 does not fit in 64 bits. Types §9.1/§11 settle the semantics ("out-of-range
## is a compile error, never a silent wrap"), but the parser had no such check: the literal ran
## through `dec_val`'s CHECKED multiply, which trapped, and the COMPILER died with SIGILL (rc 132,
## core dumped) and NO diagnostic at all. It must be a located reject.
main := fn() -> u64 {
  x : u64 = 18446744073709551616
  return x
}
