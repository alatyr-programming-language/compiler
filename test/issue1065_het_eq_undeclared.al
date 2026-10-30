## Issue #1065: a comparison over two different types with no declared relation is ill-formed.
##
## Stdlib appendix §2.6: a comparison site is well-formed when a comparison relation is DECLARED for its
## operand pair; same-type pairs take the structural default, and a heterogeneous pair of the author's
## own types is declared only by a concrete `eq(in a : A, in b : B)`. No such `eq` exists here, so
## `a == b` over `A × B` must be refused at compile time.
##
## Measured on x86_64 at 2cf60b45: it builds and returns 42. Both operands are structs of one `u64`,
## `ty_eq` compares kinds, and the structural compare of 42 with 42 succeeds.
##
## The deviation on each backend is a row of scripts/known-deviations.tsv naming #1065.
A := struct { v : u64 }
B := struct { w : u64 }
main := fn() -> u64 {
  a := A(v = 42)
  b := B(w = 42)
  if a == b { return 42 }
  return 1
}
## expect: reject
