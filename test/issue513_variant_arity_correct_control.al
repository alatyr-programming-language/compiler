## Issue #513 CONTROL — the CORRECT arity must stay accepted, on both of the enum's variants and on a
## third, WIDER one. Green on the parent and on the fix: this is the row that would catch an arity rule
## that fired on the shape rather than on the mismatch. Three distinct declared counts (1, 2 and 3) go
## through the same constructor path in one program, and each arm reads every payload word it wrote, so
## a rule that compared against the enum's widest variant instead of each variant's own declaration
## would fail here. Returns 9 + 33 + 0 = 42 (the wide arm contributes 12 + 13 + 14 - 39).
Pay := enum { A(u64), B(u64, u64), C(u64, u64, u64) }

pick := fn(k : u64) -> Pay {
  if k == 0 { return Pay.A(9) }
  if k == 1 { return Pay.B(7, 26) }
  Pay.C(12, 13, 14)
}

sum := fn(p : Pay) -> u64 {
  match p {
    A(x) => { x }
    B(a, b) => { a + b }
    C(a, b, c) => { a + b + c - 39 }
  }
}

main := fn() -> u64 {
  sum(pick(0)) + sum(pick(1)) + sum(pick(2))
}
