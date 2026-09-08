## Issue #589 / Declarations §5 + §6.1 — a bind, a PARAMETER or a LOCAL named like a module-level
## CONSTANT shadows it, and a read of that name must mean the inner binding. Scope is lexical and
## block-structured and a function (its parameters and its body) is an inner scope of the module, so
## the inner name wins for the extent of that scope.
##
## On the parent it did not on x86_64. `lower::assign::emit_st_assign` opens with
## `mut v := const_rhs(v, cx.decls, cx.src)`, and `lower::module_const_value` matches on the NAME
## alone — it filters the DECLARATION (non-`fn`, `kind == 0`, `ret_tl == 0`, `arity == 0`, not `mut`)
## and never asks whether the function being emitted has a home for that name. So `K := 3` at module
## level with `f := fn(K : f64)` called with 41.5 stored the constant's 3 from a clean compile, exit
## 0, no diagnostic. The three non-x86 backends already answered the parameter, because #574's
## resolution on those backends had to carry a bind/parameter/local guard to avoid reproducing this.
##
## That asymmetry is why this row matters more than its shape suggests: x86_64 is the WRONG column,
## so the cross-target sweeps — which compare aarch64, riscv64 and wasm AGAINST x86_64 — could only
## ever report three disagreements against a wrong baseline, or, for a shape absent from their
## corpus, nothing at all. A defect in the comparison's own reference is invisible to the comparison.
##
## Every case is CLASSIFIED rather than compared, because "not 3" is not evidence: `class` separates
## the correct inner value (0) from the MODULE CONSTANT's own 3 (1), from a zero or uninitialised
## read (2), and from any other value including a neighbouring case's (3). Each shadowing binding
## carries its OWN value (41..47), so no case can pass by reading another's slot and no pair of
## wrong answers sums to a right one. The code returned is `10 * case + class` of the FIRST failing
## case; 99 is returned only when all eleven cases are correct. Failure codes run 11..113, 99 is not
## in that set (it would need a twelfth class), and every code is below 126 (#386), so wasm's
## `proc_exit` accepts them all and no misclassification aliases onto the sentinel.
##
## Cases 8 to 11 are the OVER-EAGERNESS controls, and they are the half that decides the shape of the
## fix. 8 and 9 are the UNSHADOWED arrivals — an integer local and, the shape #574 had just made
## correct on all four backends, a float local — which must still resolve the constant. 10 and 11 are
## the ORDER controls from Declarations §7.2, where a local is visible only from its point of
## declaration onward: `K : u64 = K` reads the CONSTANT in its own initializer, and a read placed
## BEFORE a later local `K` reads the constant too. All four backends already answer 3 for both, and
## a shadow guard that asks "is this name a slot anywhere in the function" instead of "is it a slot
## DECLARED BEFORE this statement" turns both of them into a fresh silent 0 while still fixing cases
## 1 to 7 — measured on this tree, which is what puts them here.
##
## Deliberately NOT here: a shadowed `str`, struct, array or enum constant (#598). Refusing the
## resolution for those would also have to move the frame-slot size `collect_slots` reserves from its
## own `const_rhs` call, and on the three non-x86 backends they trap or diverge already, so they keep
## the path they take today. The const-STRUCT-FIELD base (`C.k` with a parameter named `C`) is absent
## for a different reason (#597): all four backends answer the constant there, so it is one agreed
## defect rather than an x86_64 divergence, and a cross-backend row asserting the correct answer
## could not pass.
##
## Why every case carries its OWN module constant (K1..K11) instead of one shared `K`: on aarch64,
## riscv64 and wasm a module constant and a same-named local in ANOTHER function share storage, so
## once a shadowing case has RUN, a later case's read of that constant answers the local's value
## (#596). The first draft of this fixture used one `K` and reported 83 on all three non-x86 backends
## for that reason alone, masking what it is here to measure. A per-case constant removes the
## coupling; #596 keeps its own reproducers.
K1 := 3

K2 := 3

K3 := 3

K4 := 3

K5 := 3

K6 := 3

K7 := 3

K8 := 3

K9 := 3

K10 := 1122334455

K11 := 987654321

## `got == want` first, so a control whose correct answer IS its module constant classifies as
## correct rather than as the defect. Class 1 is that constant leaking past a shadowing binding — the
## defect this fixture exists for, and `konst` is passed in rather than hard-coded so a case can
## choose a constant value no other case produces; class 2 is the zero a lost read defaults to;
## class 3 is any other value, including another case's.
classify := fn(got : i64, want : i64, konst : i64) -> u64 {
  if got == want {
    return 0
  }
  if got == konst {
    return 1
  }
  if got == 0 {
    return 2
  }
  return 3
}

## 1 — an `f64` PARAMETER named like the constant. The reproducer in the issue.
case1 := fn(K1 : f64) -> i64 {
  a : f64 = K1
  return i64(a)
}

## 2 — an `f64` LOCAL named like the constant. The issue's second reproducer; a local and a parameter
## are different homes for the name, so both are checked.
case2 := fn() -> i64 {
  K2 : f64 = 42.5
  a : f64 = K2
  return i64(a)
}

## 3 — a `u64` PARAMETER: the same shadow with no float conversion anywhere in the statement, so the
## case cannot pass because a conversion happened to be declined.
case3 := fn(K3 : u64) -> i64 {
  a : u64 = K3
  return i64(a)
}

## 4 — a `u64` LOCAL.
case4 := fn() -> i64 {
  K4 : u64 = 44
  a : u64 = K4
  return i64(a)
}

## 5 — an UNANNOTATED bind (`a := K`) from a parameter: the annotation is not what makes the name
## resolve, so the shape is checked without one.
case5 := fn(K5 : u64) -> i64 {
  a := K5
  return i64(a)
}

## 6 — an UNANNOTATED bind from a local.
case6 := fn() -> i64 {
  K6 := 46
  a := K6
  return i64(a)
}

## 7 — a COMPTIME local: a third home for the name, kept in the side table rather than a frame slot,
## so the guard has to ask about that table too and not only about frame slots.
case7 := fn() -> i64 {
  comptime K7 := 47
  a : u64 = K7
  return i64(a)
}

## 8 — control: UNSHADOWED, an integer local. The constant must still resolve.
case8 := fn() -> i64 {
  n : u64 = K8
  return i64(n)
}

## 9 — control: UNSHADOWED, a float local — the TYP-13 arrival #574 had just made agree on all four
## backends. A guard that fires too widely takes this straight back to 0 on three of them.
case9 := fn() -> i64 {
  a : f64 = K9
  return i64(a)
}

## 10 — control (Declarations §7.2): the DECLARATION's own initializer. The local is visible only
## from its point of declaration onward, so the name on the right is the module constant. `K10` and
## `K11` carry a DISTINCTIVE value rather than 3 because a control whose correct answer is the
## constant's own value can otherwise be satisfied by an uninitialised frame word that happens to
## hold it — measured: with the order restriction removed, this case reported the class-2 zero when
## run alone but passed inside the aggregate, because an earlier `classify(…, 3)` had left a 3 in the
## frame word the lost read reached. A value no other case produces removes that coincidence.
case10 := fn() -> i64 {
  K10 : u64 = K10
  return i64(K10)
}

## 11 — control (Declarations §7.2), the other direction: the read is placed BEFORE the local `K`
## that would shadow it, so it is the constant that is read.
case11 := fn() -> i64 {
  n : u64 = K11
  K11 : u64 = 41
  return i64(n)
}

main := fn() -> u64 {
  k1 := classify(case1(41.5), 41, 3)
  if k1 != 0 {
    return 10 + k1
  }
  k2 := classify(case2(), 42, 3)
  if k2 != 0 {
    return 20 + k2
  }
  k3 := classify(case3(43), 43, 3)
  if k3 != 0 {
    return 30 + k3
  }
  k4 := classify(case4(), 44, 3)
  if k4 != 0 {
    return 40 + k4
  }
  k5 := classify(case5(45), 45, 3)
  if k5 != 0 {
    return 50 + k5
  }
  k6 := classify(case6(), 46, 3)
  if k6 != 0 {
    return 60 + k6
  }
  k7 := classify(case7(), 47, 3)
  if k7 != 0 {
    return 70 + k7
  }
  k8 := classify(case8(), 3, 3)
  if k8 != 0 {
    return 80 + k8
  }
  k9 := classify(case9(), 3, 3)
  if k9 != 0 {
    return 90 + k9
  }
  k10 := classify(case10(), 1122334455, 1122334455)
  if k10 != 0 {
    return 100 + k10
  }
  k11 := classify(case11(), 987654321, 987654321)
  if k11 != 0 {
    return 110 + k11
  }
  99
}
