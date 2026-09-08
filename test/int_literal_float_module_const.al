## TYP-13 / Types §9.1 (#574). An integer literal in a floating-point context is converted to the
## floating value; a MODULE CONSTANT and a depth-1 CONST-STRUCT FIELD that the compiler itself
## resolves to that integer literal are the same initializer, so the four backends must not disagree
## about the value. They did: the x86_64 lower normalizes the RHS through `lower::const_rhs` (and the
## `Expr::Field` arm beside it) before it asks the TYP-13 question, so `a : f64 = K` reached its
## predicate already resolved to an `Expr::Num` — while `grep -c const_rhs` over the three non-x86
## emitters was `0 0 0`, so theirs received an `Expr::Var`/`Expr::Field`, answered "not an integer
## constant", and the generic scalar path stored the integer bits unchanged for a later read to
## interpret as a denormal. Both forms answered 3 on x86_64 and 0 on aarch64, riscv64 and wasm, from
## a clean compile with no diagnostic. This is the other half of #558's divergence: that one gave the
## `unchecked` wrapper content in the same four predicate copies, this one gives them the constant
## resolution step three of them never had.
##
## Every case is CLASSIFIED, not merely compared, because 0 is both the observed defect (a denormal
## read back) and the commonest default of any broken read: `class` separates a correct value (0)
## from that zero (1), from a magnitude-losing truncation (2), and from anything else (3). The code
## returned is `10 * case + class` of the FIRST failing case, so a failure names the case AND the
## outcome class; 99 is returned only when all nine cases are correct. Failure codes run 11..93, 99
## is outside that range, and every code is below 126 (#386), so no misclassification can alias onto
## the success sentinel and wasm's `proc_exit` accepts them all.
##
## Case 7 is the four-outcome seam (#444's argument, applied to magnitude because the SIGN seam is
## unavailable here): 4294967297 is exactly representable in f64, so a lost conversion reads back 0
## (class 1), a conversion truncated to 32 bits reads back 1 (class 2), and anything else is class 3
## — three distinct wrong answers this one case tells apart. A negative constant cannot be used at
## this seam: on the parent tree `K := -5` with an INTEGER local already traps (133) on aarch64 and
## riscv64 and reads back 0 on wasm, before the float conversion is reached at all, so a negative
## case here would fail for that separate defect (#590) rather than for this one.
##
## Cases 8 and 9 are the OVER-EAGERNESS controls, and they are why the fix cannot be "convert any
## constant": an INTEGER-annotated local fed by the same constant and the same const-struct field
## must keep the integer, unconverted. A conversion leaking into them reads back the f64 bit image
## of 3.0 (4613937818241073152), which is class 3, not the class-1 zero every other regression here
## produces. A name SHADOWED by a parameter or a local is deliberately absent from this fixture: the
## four backends disagree there for a different reason (#589, where x86_64 is the wrong column), and a
## cross-backend row asserting the correct answer could not pass on x86_64 today.
K3 := 3
K7 := 7
KB := 16777216
KL := 4294967297
S := struct { k : u64, m : u64 }
C := S(k = 3, m = 7)

classify := fn(got : i64, want : i64) -> u64 {
  if got == want { return 0 }
  if got == 0 { return 1 }
  if want > 0 and got > 0 and got < want { return 2 }
  if want < 0 and got < 0 and got > want { return 2 }
  return 3
}

main := fn() -> u64 {
  ## 1 — f64 local from a module constant.
  c1 : f64 = K3
  k1 := classify(i64(c1), 3)
  if k1 != 0 { return 10 + k1 }

  ## 2 — f32 local from a module constant.
  c2 : f32 = K7
  k2 := classify(i64(c2), 7)
  if k2 != 0 { return 20 + k2 }

  ## 3 — f64 local from a depth-1 const-struct field.
  c3 : f64 = C.k
  k3 := classify(i64(c3), 3)
  if k3 != 0 { return 30 + k3 }

  ## 4 — f32 local from a depth-1 const-struct field, reading the SECOND field so the positional
  ## field-to-argument pairing is exercised rather than only the head of the argument list.
  c4 : f32 = C.m
  k4 := classify(i64(c4), 7)
  if k4 != 0 { return 40 + k4 }

  ## 5 — the constant arrival agrees with the direct-literal spelling, which was already correct on
  ## every backend. Measured against the literal itself rather than inferred from two constants.
  p5 : f64 = 3
  k5 := classify(i64(c1), i64(p5))
  if k5 != 0 { return 50 + k5 }

  ## 6 — the f32 exact-representability ceiling: 16777216 is the largest power of two f32 still holds
  ## exactly, so a lost conversion here is class 1 while a narrowing error is class 2 or 3.
  c6 : f32 = KB
  k6 := classify(i64(c6), 16777216)
  if k6 != 0 { return 60 + k6 }

  ## 7 — the four-outcome magnitude seam described in the header.
  c7 : f64 = KL
  k7 := classify(i64(c7), 4294967297)
  if k7 != 0 { return 70 + k7 }

  ## 8 — control: an INTEGER local from the same module constant keeps the integer.
  n8 : u64 = K3
  k8 := classify(i64(n8), 3)
  if k8 != 0 { return 80 + k8 }

  ## 9 — control: an INTEGER local from the same const-struct field keeps the integer.
  n9 : u64 = C.k
  k9 := classify(i64(n9), 3)
  if k9 != 0 { return 90 + k9 }

  99
}
