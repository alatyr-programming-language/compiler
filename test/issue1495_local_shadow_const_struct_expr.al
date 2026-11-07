## Issue #1495 / Declarations §5 + §6.1 + §7.2 — a LOCAL named like a module-level CONST STRUCT owns that
## name from its declaration on, so `<name>.<field>` read in EXPRESSION position (`return C.k`, an operand,
## a call argument) is the LOCAL's field, not the constant's compile-time value. Scope is lexical and
## block-structured, a function body is an inner scope of the module (§5), "within the inner scope the inner
## name wins" (§6.1), and a name is visible from its declaration on (§7.2). DECIDED at the pinned 1.8.0.
##
## This pins the COMBINATION `test/issue597_shadowed_const_struct_field.al` left untested: that fixture
## covers a LOCAL only through an assignment (`a : u64 = C.k`, its case 2) and EXPRESSION position only
## through a PARAMETER (its cases 3 and 4). Here every shadowing binding is a local and every read is an
## expression. #1495 reported x86_64 answering the constant (7 where 50 is due); re-measured on omen on
## main 7621cdfe with Stage1 that is NOT so — x86_64, aarch64, riscv64 and wasm answer the local — and the
## issue's column came from a compiler WITHOUT #1480 (`6f3b4a4b` is not a descendant of #1480's merge
## `ae56e6f2`). The committed seed (0.2.21, pre-#1480) reproduces it: built by the seed this fixture
## answers 11 (case 1, class 1, the constant's own field). So the fixture is a regression pin for #1480's
## `emit_gas` `Expr::Field` guard on the local spelling, not a new fix.
##
## Every case is CLASSIFIED, not compared: class 0 is the local's value, 1 the MODULE CONSTANT's own field
## value (the defect), 2 a zero or lost read, 3 anything else, including a neighbouring case's value. Each
## case has its OWN module constant (C1..C5) whose field values no other case produces, and its own local
## value, so no case passes by reading another case's slot (on aarch64, riscv64 and wasm a module constant
## and a same-named local in another function can share storage, #596). The code is `10 * case + class` of
## the FIRST failing case: 11..53, never 99, every code below 126 so wasm's `proc_exit` accepts it.
##
## Cases 1 and 2 are #1495's first two table rows: a local then `return C.k`, and the same inside an `if`
## block. Case 3 reads both fields as OPERANDS of a binary expression, case 4 passes the field as a CALL
## ARGUMENT, case 5 reads the SECOND field so the positional field-to-argument pairing is exercised.
##
## Deliberately NOT here: #1495's rows 3 and 4, the §7.2 ORDER spelling (`a : u64 = C.k` BEFORE the local
## `C`). On main they answer 50 and 57 on x86_64, aarch64 and riscv64, but TRAP on wasm (134), which is
## #1496; a row asserted on all four backends would fold that separate wasm gap in. #1496's fix owns them.
S := struct { k : u64, m : u64 }

C1 := S(k = 121, m = 122)
C2 := S(k = 123, m = 124)
C3 := S(k = 125, m = 126)
C4 := S(k = 127, m = 128)
C5 := S(k = 129, m = 130)

## `got == want` first, so only a value that is NOT the local's can be the constant's.
classify := fn(got : u64, want : u64, konst : u64) -> u64 {
  if got == want { return 0 }
  if got == konst { return 1 }
  if got == 0 { return 2 }
  return 3
}

g := fn(x : u64) -> u64 { return x }

## 1 — #1495 row 1: a local `C1`, then `return C1.k`.
case1 := fn() -> u64 { C1 := S(k = 51, m = 0) ; return C1.k }

## 2 — #1495 row 2: the same local and read inside an `if` block.
case2 := fn(t : u64) -> u64 {
  if t == 1 { C2 := S(k = 52, m = 0) ; return C2.k }
  return 0
}

## 3 — both fields as OPERANDS of a binary expression: 53 + 1, where the constant would give 125 + 126.
case3 := fn() -> u64 { C3 := S(k = 53, m = 1) ; return C3.k + C3.m }

## 4 — the field as a CALL ARGUMENT.
case4 := fn() -> u64 { C4 := S(k = 55, m = 0) ; return g(C4.k) }

## 5 — the SECOND field in expression position.
case5 := fn() -> u64 { C5 := S(k = 0, m = 56) ; return C5.m }

main := fn() -> u64 {
  k1 := classify(case1(), 51, 121)
  if k1 != 0 { return 10 + k1 }
  k2 := classify(case2(1), 52, 123)
  if k2 != 0 { return 20 + k2 }
  k3 := classify(case3(), 54, 251)
  if k3 != 0 { return 30 + k3 }
  k4 := classify(case4(), 55, 127)
  if k4 != 0 { return 40 + k4 }
  k5 := classify(case5(), 56, 130)
  if k5 != 0 { return 50 + k5 }
  99
}
## expect: run 99
