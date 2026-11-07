## Issue #1497 / Declarations §5 + §6.1 — a local declared INSIDE a block shadows a module constant of
## the same name only WITHIN that block. Scope is lexical and block-structured (§5), and "within the inner
## scope the inner name wins" (§6.1): once the block has closed, the name means the module constant again.
##
## On x86_64 it did not. #1480's shadow guard `lower::slot_declared_before` asked only whether a frame
## slot of that name was declared EARLIER IN THE SOURCE, never whether the block that declared it was
## still open. So a read of `C.k` after `if t == 1 { C := S(k = 50, m = 0) }` declined the constant and
## read the dead local's slot: the issue's reproducer answered 50 where 7 is due, from a clean compile
## with no diagnostic.
##
## Every case is CLASSIFIED, not compared: class 0 is right; class 1 is the WRONG binding's value (the
## dead local's in cases 1..8 and 13, the constant's in the controls); class 2 is zero; class 3 is anything
## else. Each case has its OWN module constant and its own local value, distinct from every other case,
## so no case passes by reading another's slot (#596 couples a constant with a same-named local in
## another function on the twins). The exit code is `4 * case + class` of the FIRST failing case, 99
## when all thirteen hold; the codes run 5..55, 99 is not one of them, and all are below 126.
##
## 1  the issue's reproducer: a struct local in an `if` block, the field read in a declaration after it.
## 2  the same, read in EXPRESSION position (`return C.k`, `emit_gas`' `Expr::Field` arm).
## 3  SIBLING blocks: one `if` block declares the local, a later `if` block reads the name.
## 4  a `while` body declares the local; the read follows the loop.
## 5  a `for` body declares the local; the read follows the loop.
## 6  a SCALAR constant (#589's half, `const_rhs_unshadowed`): `K6 := 60` in a block, `a : u64 = K6`
##    after it.
## 7  a `for` loop VARIABLE named like a scalar constant: its scope is the loop body only.
## 8  the block nests two deep and both close before the read.
## 13 a match-arm PATTERN binding `Some(C13)`; the read follows the `match`.
## 9..12 are the OVER-EAGERNESS controls: the local is still in scope, so its value is due, and each
##    passes on the parent too. 9 reads after a NESTED block inside the declaring block has closed;
##    10 reads after a closing brace inside a char literal and inside a comment, neither of which closes
##    anything; 11 reads inside the `for` body, where the loop variable is in scope; 12 declares the
##    name again in a SIBLING block and reads it there. The slot map keeps only the first declaration
##    (#406), and that one is out of scope by then.
##
## Registered on x86_64 only. aarch64 and riscv64 have a different defect (#1502): their emitters
## resolve the name to the module binding's `.data` label before any frame slot, so the block-local
## declaration would overwrite the constant (they answered 5 here before #1502's stub). They trap on
## that declaration (133) instead, and so does wasm (134), whose own trap here is #1496. Known deviations.
S := struct { k : u64, m : u64 }

C1 := S(k = 7, m = 8)
C2 := S(k = 9, m = 10)
C3 := S(k = 11, m = 12)
C4 := S(k = 13, m = 14)
C5 := S(k = 15, m = 16)
K6 := 17
K7 := 19
C8 := S(k = 21, m = 22)
C9 := S(k = 23, m = 24)
C10 := S(k = 25, m = 26)
K11 := 27
C12 := S(k = 29, m = 30)
C13 := S(k = 31, m = 32)

classify := fn(got : u64, want : u64, dead : u64) -> u64 {
  if got == want { return 0 }
  if got == dead { return 1 }
  if got == 0 { return 2 }
  return 3
}

case1 := fn(t : u64) -> u64 {
  if t == 1 { C1 := S(k = 50, m = 0) ; x : u64 = C1.k ; if x != 50 { return 3 } }
  a : u64 = C1.k
  return a
}

case2 := fn(t : u64) -> u64 {
  if t == 1 { C2 := S(k = 52, m = 0) ; x : u64 = C2.k ; if x != 52 { return 3 } }
  return C2.k
}

case3 := fn(t : u64) -> u64 {
  if t == 1 { C3 := S(k = 54, m = 0) ; x : u64 = C3.k ; if x != 54 { return 3 } }
  mut a : u64 = 0
  if t == 1 { a = C3.k }
  return a
}

case4 := fn(t : u64) -> u64 {
  mut i : u64 = 0
  while i < t { C4 := S(k = 56, m = 0) ; x : u64 = C4.k ; if x != 56 { return 3 } ; i += 1 }
  a : u64 = C4.k
  return a
}

case5 := fn(t : u64) -> u64 {
  for i in 0 .. t { C5 := S(k = 58, m = 0) ; x : u64 = C5.k ; if x != 58 { return 3 } }
  a : u64 = C5.k
  return a
}

case6 := fn(t : u64) -> u64 {
  if t == 1 { K6 := 60 ; x : u64 = K6 ; if x != 60 { return 3 } }
  a : u64 = K6
  return a
}

case7 := fn(t : u64) -> u64 {
  mut s : u64 = 0
  for K7 in 0 .. t { s += K7 }
  a : u64 = K7
  return a + s
}

case8 := fn(t : u64) -> u64 {
  if t == 1 { if t == 1 { C8 := S(k = 62, m = 0) ; x : u64 = C8.k ; if x != 62 { return 3 } } }
  a : u64 = C8.k
  return a
}

case9 := fn(t : u64) -> u64 {
  mut a : u64 = 0
  if t == 1 {
    C9 := S(k = 64, m = 0)
    if t == 1 { a = 1 }
    a = C9.k
  }
  return a
}

case10 := fn(t : u64) -> u64 {
  mut a : u64 = 0
  if t == 1 {
    C10 := S(k = 66, m = 0)
    b : u32 = '}'      # } a brace in a comment closes nothing
    a = C10.k + u64(b) - 125
  }
  return a
}

case11 := fn(t : u64) -> u64 {
  mut a : u64 = 0
  for K11 in 68 .. 68 + t { if t == 1 { a = 1 } ; a = K11 }
  return a
}

case12 := fn(t : u64) -> u64 {
  mut a : u64 = 0
  if t == 1 { C12 := S(k = 70, m = 0) ; a = C12.k }
  if t == 1 { C12 := S(k = 72, m = 0) ; a = C12.k }
  return a
}

case13 := fn(o : Option(S)) -> u64 {
  mut r : u64 = 0
  match o { Some(C13) => { r = C13.k } ; None => { r = 1 } }
  a : u64 = C13.k
  return a + r
}

main := fn() -> u64 {
  k1 := classify(case1(1), 7, 50)
  if k1 != 0 { return 4 + k1 }
  k2 := classify(case2(1), 9, 52)
  if k2 != 0 { return 8 + k2 }
  k3 := classify(case3(1), 11, 54)
  if k3 != 0 { return 12 + k3 }
  k4 := classify(case4(1), 13, 56)
  if k4 != 0 { return 16 + k4 }
  k5 := classify(case5(1), 15, 58)
  if k5 != 0 { return 20 + k5 }
  k6 := classify(case6(1), 17, 60)
  if k6 != 0 { return 24 + k6 }
  k7 := classify(case7(1), 19, 1)
  if k7 != 0 { return 28 + k7 }
  k8 := classify(case8(1), 21, 62)
  if k8 != 0 { return 32 + k8 }
  k9 := classify(case9(1), 64, 23)
  if k9 != 0 { return 36 + k9 }
  k10 := classify(case10(1), 66, 25)
  if k10 != 0 { return 40 + k10 }
  k11 := classify(case11(1), 68, 27)
  if k11 != 0 { return 44 + k11 }
  k12 := classify(case12(1), 72, 29)
  if k12 != 0 { return 48 + k12 }
  k13 := classify(case13(Option(S).Some(S(k = 74, m = 0))), 105, 148)
  if k13 != 0 { return 52 + k13 }
  99
}
## expect: run 99
