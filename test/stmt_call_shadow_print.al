## A user-declared `print` SHADOWS the prelude's comptime-variadic `std::fmt::print` (the
## built-in names are ordinary prelude identifiers, not reserved words). In STATEMENT position the
## call was routed into the `{}`-template desugar by TAIL NAME alone and then dropped (arg 0 is not
## a string literal): the user's fn never ran, the counter stayed 0, and the program exited 0 with
## no diagnostic at all. No `str` and no view is involved — the defect was never about the
## argument's type, only about resolving the callee.
mut CNT : u64 = 0
print := fn(x : u64) -> u64 { CNT = CNT + x return x }
main := fn() -> u64 {
  print(5)                ## statement position, result discarded
  mut i : u64 = 0
  while i < 2 {
    print(1)              ## inside a `while` body
    i = i + 1
  }
  if CNT == 7 {
    print(35)             ## inside an `if` branch
  }
  n := print(0)           ## value position: already worked, stays working
  return CNT
}
