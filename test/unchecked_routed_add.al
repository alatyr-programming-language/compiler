## CG-7 / CG-13: `unchecked` reaches the routed operator body but suppresses the operation-site
## checked guard. `std::io` injects `base::num`; MAX+1 therefore wraps to zero, and the in-program
## classification returns 42 instead of relying on an ambiguous exit code.
add := fn(a : u64, b : u64) -> u64 { return unchecked (a + b) }
main := fn() -> u64 {
  z := std::io::print("")
  r := add(18446744073709551615, 1)
  if r == 0 { return 42 }
  7
}
