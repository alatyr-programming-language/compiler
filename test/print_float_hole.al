## e2e — a `{}`-template `print` hole filled by a FLOAT. A float local records no slot type span and
## its value lives in an xmm register at the call boundary, so the desugar detects it by slot kind
## (ek 9) and routes it to the non-generic `print_one_float` with the value in %xmm0. Prints
## "x = 3.5" (verified manually) and returns 42 — checks the float-hole path compiles, links, runs.
main := fn() -> u64 {
  x : f64 = 3.5
  std::fmt::print("x = {}\n", x)
  42
}
