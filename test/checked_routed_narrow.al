## CG-8 / CG-13 width companion: the shipped `base::num` operator for a narrow integer has no
## library panic guard. The checked operation-site guard still catches the u8 result before the raw
## routed body truncates it. `std::io` makes the routed stdlib path explicit; 200+100 must exit 132.
add := fn(a : u8, b : u8) -> u8 { return a + b }
main := fn() -> u64 {
  z := std::io::print("")
  return u64(add(200, 100)) + u64(z)
}
