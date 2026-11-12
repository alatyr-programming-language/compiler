## Issue #598 / Declarations §5 + §6.1 — a PARAMETER or a LOCAL named like a module-level `str` or STRUCT
## CONSTANT owns that name inside its scope, so binding from it copies the INNER value, not the constant's.
## Scope is lexical and block-structured and a function (its parameters and its body) is an inner scope of the
## module (§5); a declaration in an inner scope may shadow an outer name and "within the inner scope the inner
## name wins" (§6.1). DECIDED at the pinned revision 1.9.0 (tag v1.9.0, commit 60bf006).
##
## On the parent it did not. `lower::assign::const_rhs_unshadowed` — #589's shadow guard — asked the right
## question and then DECLINED to answer it for anything but a one-word scalar: its second act was
## `if const_scalar_lit(r) == false { return r }`, so a `StrLit` or a `StructLit` constant returned the
## CONSTANT before the shadow question was ever reached. `f := fn(M : str) -> u64 { s : str = M }` called
## with `"abcdefgh"` therefore bound `"abc"`, and `f := fn(C : S) -> u64 { p : S = C }` called with
## `S(k = 41, m = 5)` bound `S(k = 3, m = 4)`. Clean compile, exit 0, no diagnostic.
##
## Why #589 stopped there, and why this may pass it. #589 recorded that refusing the resolution for a `str`,
## struct, array or enum constant "would also have to move the frame-slot size `collect_slots` reserves from
## its OWN `const_rhs` call". For `str` and struct that turns out not to bind: checked sema has already
## forced the binding's type and the constant's type to agree, so a `str` RHS is a two-word {ptr,len} view
## whichever value it is given and a struct RHS is that struct's own word block either way — `collect_slots`
## reserves the same words and needs no matching edit. An ARRAY or ENUM constant is NOT widened here: a module
## const array takes `.data` storage under a label (`const_array_value`, `global_needs_storage`) while a local
## array lives in frame words, so declining there would change the shape as well as the value. A shadowed array
## or enum constant still answers the constant, which §6.1 makes a wrong value; it is filed as #1565 and is
## not pinned here. Case 9 is only the UNSHADOWED array arrival.
##
## The same guard is asked at the CALL-ARGUMENT position (`emit_arg`'s `str`-constant arm): a shadowing `str`
## parameter or local passed straight into a call (`f := fn(M : str) -> u64 { return g(M) }`) sent the
## constant there too. Cases 10–12.
##
## Every case is CLASSIFIED rather than compared, because "not 3" is not evidence: `class` separates the
## correct INNER value (0) from the MODULE CONSTANT's own value (1 — the defect this fixture exists for), from
## a zero or lost read (2), and from any other value including a neighbouring case's (3). Each case carries its
## OWN constant with a value NO other case produces, and each shadowing binding carries its OWN distinct
## value, so no case can pass by reading another's slot. The code returned is `10 * case + class` of the
## FIRST failing case; 99 only when all twelve are correct. Failure codes run 11..93 and 101..123, 99 is
## outside that set, and every code is below 126 (#386).
##
## REGISTERED ON x86_64 ONLY (`run_x86`), deliberately. Measured on this tree, the `str` rows TRAP on all
## three twins in BOTH spellings — shadowed (`s : str = M` from a parameter: aarch64 133, riscv64 133, wasm
## 134) and UNSHADOWED (`s : str = M` from the constant itself: the same 133/133/134) — so a cross-backend
## row could not pass without folding a separate pre-existing backend gap into this issue. The struct rows do
## run on all four (shadowed parameter and shadowed local: aarch64/riscv64/wasm 41 and 46), except the
## UNSHADOWED struct-copy of a const struct reading the SECOND field, which traps on riscv64 and wasm. Those
## loud traps are not wrong values and are reported to the integrator as residuals; #598 itself states the
## three non-x86 columns "are not required to move by this issue".
##
## Deliberately NOT here: the const-struct FIELD base (`C.k` with a parameter named `C`), which is #597 and
## is guarded in `lower::const_struct_field` — a different position, answered by the same `name_shadowed`.
S := struct { k : u64, m : u64 }

M1 := "abc"
M3 := "hi"
M5 := "x"
M7 := "abcdef"
C2 := S(k = 103, m = 104)
C4 := S(k = 107, m = 108)
C6 := S(k = 109, m = 110)
C8 := S(k = 113, m = 114)
A9 : [u64; 3] = [10, 20, 30]
M10 := "abcd"
M11 := "abcdefghi"
M12 := "abcdefghijk"

## `got == want` FIRST, so a control whose correct answer IS its constant classifies as correct.
classify := fn(got : u64, want : u64, konst : u64) -> u64 {
  if got == want { return 0 }
  if got == konst { return 1 }
  if got == 0 { return 2 }
  return 3
}

## 1 — a `str` PARAMETER named `M1`. The issue's first reproducer, verbatim shape.
case1 := fn(M1 : str) -> u64 { s : str = M1 ; return u64(s.len) }

## 2 — a STRUCT PARAMETER named `C2`, copied. The issue's second reproducer, verbatim shape.
case2 := fn(C2 : S) -> u64 { p : S = C2 ; return p.k }

## 3 — a `str` LOCAL named `M3`: a parameter and a local are different homes for the name.
case3 := fn() -> u64 { M3 := "hello" ; s : str = M3 ; return u64(s.len) }

## 4 — a STRUCT LOCAL named `C4`, copied.
case4 := fn() -> u64 { C4 := S(k = 46, m = 47) ; p : S = C4 ; return p.k }

## 5 — a second `str` PARAMETER with a length no other case produces, so the case cannot pass off case 1's
## binding or a default length.
case5 := fn(M5 : str) -> u64 { s : str = M5 ; return u64(s.len) }

## 6 — the SECOND field of a shadowed struct parameter, so the copy is exercised past word 0.
case6 := fn(C6 : S) -> u64 { p : S = C6 ; return p.m }

## 7 — control: UNSHADOWED `str` constant arrival. Must STILL resolve the constant.
case7 := fn() -> u64 { s : str = M7 ; return u64(s.len) }

## 8 — control: UNSHADOWED struct constant arrival. Must STILL resolve the constant.
case8 := fn() -> u64 { p : S = C8 ; return p.k }

## 9 — control: UNSHADOWED array constant arrival, no binding named `A9` anywhere. Must STILL answer the
## constant's element. It pins only that arrival; a SHADOWED array (or enum) constant is a separate silent
## wrong value, filed as #1565, and nothing here claims the constant is the right answer there.
case9 := fn() -> u64 { return A9[1] }

## The CALL-ARGUMENT position: `emit_arg` resolved a bare `str` name through the module table before the
## binding forms were ever consulted, so a shadowing name passed straight into a call still sent the constant.
len10 := fn(s : str) -> u64 { return u64(s.len) }

## 10 — a `str` PARAMETER named `M10` passed straight as a call argument.
case10 := fn(M10 : str) -> u64 { return len10(M10) }

## 11 — a `str` LOCAL named `M11` passed straight as a call argument.
case11 := fn() -> u64 { M11 := "abcdefg" ; return len10(M11) }

## 12 — control: the UNSHADOWED `str` constant passed as a call argument. Must STILL resolve the constant.
case12 := fn() -> u64 { return len10(M12) }

main := fn() -> u64 {
  k1 := classify(case1("abcdefgh"), 8, 3)
  if k1 != 0 { return 10 + k1 }
  k2 := classify(case2(S(k = 41, m = 5)), 41, 103)
  if k2 != 0 { return 20 + k2 }
  k3 := classify(case3(), 5, 2)
  if k3 != 0 { return 30 + k3 }
  k4 := classify(case4(), 46, 107)
  if k4 != 0 { return 40 + k4 }
  k5 := classify(case5("abcdefghijkl"), 12, 1)
  if k5 != 0 { return 50 + k5 }
  k6 := classify(case6(S(k = 51, m = 52)), 52, 110)
  if k6 != 0 { return 60 + k6 }
  k7 := classify(case7(), 6, 6)
  if k7 != 0 { return 70 + k7 }
  k8 := classify(case8(), 113, 113)
  if k8 != 0 { return 80 + k8 }
  k9 := classify(case9(), 20, 20)
  if k9 != 0 { return 90 + k9 }
  k10 := classify(case10("abcdefghij"), 10, 4)
  if k10 != 0 { return 100 + k10 }
  k11 := classify(case11(), 7, 9)
  if k11 != 0 { return 110 + k11 }
  k12 := classify(case12(), 11, 11)
  if k12 != 0 { return 120 + k12 }
  99
}
## expect: run 99
