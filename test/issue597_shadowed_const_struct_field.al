## Issue #597 / Declarations §5 + §6.1 — a PARAMETER or a LOCAL named like a module-level CONST STRUCT
## owns that name inside its scope, so `<name>.<field>` is the INNER binding's field read, not the
## constant's compile-time value. Scope is lexical and block-structured and a function (its parameters and
## its body) is an inner scope of the module (§5); a declaration in an inner scope may shadow an outer name
## and "within the inner scope the inner name wins" (§6.1).
##
## On the parent it did not, on ALL FOUR backends. `lower::const_struct_field` resolves the FIELD BASE
## through `lower::module_const_value` on the NAME ALONE: it filters the DECLARATION (non-`fn`,
## `kind == 0`, `ret_tl == 0`, `arity == 0`, not `mut`) and never asks whether the function being emitted
## has a home for that name. Three sites asked it that way — `emit_st_assign`'s normalizer
## (`const_field_rhs`, #716), `collect_slots`' slot sizing beside it, and `emit_gas`' own `Expr::Field`
## arm — so `f := fn(C : S) -> u64 { a : u64 = C.k }` called with `S(k = 41)` stored the CONSTANT's 3
## from a clean compile, exit 0, no diagnostic. #589 fixed the bare-`Var` scalar half and DECLINED this
## one on purpose: `var_name_span` of a `Field` is empty, so its guard never saw a `Field` base.
##
## Unlike #589 this was never an x86_64-only column: all four backends answered the constant, so the
## cross-target sweeps — which compare aarch64, riscv64 and wasm AGAINST x86_64 — had no divergence to
## report and could not see it either. That is why this fixture carries rows on all four backends rather
## than one: the fix must make them AGREE ON THE RIGHT ANSWER, and a row on x86_64 alone would leave the
## other three unmeasured.
##
## Every case is CLASSIFIED rather than compared, because "not 3" is not evidence: `class` separates the
## correct INNER value (0) from the MODULE CONSTANT's own field value (1 — the defect this fixture exists
## for), from a zero or lost read (2), and from any other value including a neighbouring case's (3). Each
## case carries its OWN module constant with a field value NO other case produces, and each shadowing
## binding carries its OWN distinct value, so no case can pass by reading another's slot and no pair of
## wrong answers sums to a right one. The code returned is `10 * case + class` of the FIRST failing case;
## 99 is returned only when all nine cases are correct. Failure codes run 11..93, 99 is not in that set,
## and every code is below 126 (#386), so wasm's `proc_exit` accepts them all.
##
## Cases 1 and 2 are the issue's own two reproducers, kept in their own shapes: a PARAMETER named `C`
## (case 1) and an unannotated LOCAL named `C` (case 2) — a parameter and a local are different homes for
## the name, so both are checked. Case 3 is the same shadow in EXPRESSION position (`return C.k`), which
## goes through `emit_gas`' `Expr::Field` arm rather than the assignment normalizer, and case 4 through a
## CALL ARGUMENT (`g(C.k)`); both are the third site, and a fix that guards only the assignment leaves
## them wrong. Case 5 reads the SECOND field so the positional field-to-argument pairing is exercised and
## not only the head of the literal. Case 6 is an ANNOTATED local, the spelling case 2 does not cover.
##
## Cases 7 and 8 are the OVER-EAGERNESS controls, and they are the half that decides the shape of the
## fix: a const-struct field read with NOTHING shadowing the base, first field and second field, must STILL
## resolve the constant. They are the same arrivals `test/int_literal_float_module_const.al` cases 3, 4 and
## 9 pin at 99, and a guard that asks "is this name ever a slot" instead of "is it a slot DECLARED BEFORE
## this use" turns them into a silent 0 while still fixing cases 1 to 6.
##
## Why every case carries its OWN constant (C1..C8) instead of one shared `C`: on aarch64, riscv64 and
## wasm a module constant and a same-named local in ANOTHER function share storage, so once a shadowing case
## has RUN, a later case's read of that constant answers the local's value (#596). A per-case constant
## removes the coupling; #596 keeps its own reproducers.
##
## Deliberately NOT here: (a) a shadowed `str` or struct COPY binding (`s : str = M`, `p : S = C`) — that
## is #598, which refuses through `const_rhs_unshadowed`'s `const_scalar_lit` narrowing and has to move the
## frame-slot size with it; (b) the Declarations §7.2 ORDER control where a read of `C.k` precedes a LATER
## local `C` of the same struct type. Measured on this tree, that spelling TRAPS on wasm (134) identically
## on the parent and on the fix, while x86_64 answers it correctly (115) — a pre-existing wasm gap in the
## struct-local-after-read path, not this defect and not made worse by it. It is reported to the integrator
## rather than folded in here, because a fixture that traps on one backend needs a deviation row of its own;
## the §7.2 order rule itself is already pinned on all four backends by `test/module_const_shadowed_name.al`
## case 11.
S := struct { k : u64, m : u64 }

C1 := S(k = 101, m = 102)
C2 := S(k = 103, m = 104)
C3 := S(k = 105, m = 106)
C4 := S(k = 107, m = 108)
C5 := S(k = 109, m = 110)
C6 := S(k = 111, m = 112)
C7 := S(k = 113, m = 114)
C8 := S(k = 117, m = 118)

## `got == want` FIRST, so a control whose correct answer IS the constant's own field classifies as
## correct rather than as the defect. Class 1 is that constant leaking past a shadowing binding.
classify := fn(got : u64, want : u64, konst : u64) -> u64 {
  if got == want { return 0 }
  if got == konst { return 1 }
  if got == 0 { return 2 }
  return 3
}

g := fn(x : u64) -> u64 { return x }

## 1 — a PARAMETER named `C1` shadowing the const struct. The issue's first reproducer, verbatim shape.
case1 := fn(C1 : S) -> u64 { a : u64 = C1.k ; return a }

## 2 — an unannotated LOCAL named `C2`. The issue's second reproducer, verbatim shape.
case2 := fn() -> u64 { C2 := S(k = 42, m = 0) ; a : u64 = C2.k ; return a }

## 3 — the same shadow in EXPRESSION position: `emit_gas`' `Expr::Field` arm, not the assignment.
case3 := fn(C3 : S) -> u64 { return C3.k }

## 4 — the shadow reached through a CALL ARGUMENT, the third spelling of that same arm.
case4 := fn(C4 : S) -> u64 { return g(C4.k) }

## 5 — the SECOND field of a shadowed base, so the field index is exercised too.
case5 := fn(C5 : S) -> u64 { a : u64 = C5.m ; return a }

## 6 — an ANNOTATED local named `C6`: the local spelling case 2 does not cover.
case6 := fn() -> u64 { C6 : S = S(k = 46, m = 0) ; a : u64 = C6.k ; return a }

## 7 — control: UNSHADOWED const-struct field, first field. Must STILL resolve the constant.
case7 := fn() -> u64 { a : u64 = C7.k ; return a }

## 8 — control: UNSHADOWED const-struct field, SECOND field.
case8 := fn() -> u64 { a : u64 = C8.m ; return a }

main := fn() -> u64 {
  k1 := classify(case1(S(k = 41, m = 0)), 41, 101)
  if k1 != 0 { return 10 + k1 }
  k2 := classify(case2(), 42, 103)
  if k2 != 0 { return 20 + k2 }
  k3 := classify(case3(S(k = 43, m = 0)), 43, 105)
  if k3 != 0 { return 30 + k3 }
  k4 := classify(case4(S(k = 44, m = 0)), 44, 107)
  if k4 != 0 { return 40 + k4 }
  k5 := classify(case5(S(k = 0, m = 45)), 45, 110)
  if k5 != 0 { return 50 + k5 }
  k6 := classify(case6(), 46, 111)
  if k6 != 0 { return 60 + k6 }
  k7 := classify(case7(), 113, 113)
  if k7 != 0 { return 70 + k7 }
  k8 := classify(case8(), 118, 118)
  if k8 != 0 { return 80 + k8 }
  99
}
## expect: run 99
