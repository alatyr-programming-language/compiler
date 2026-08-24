## e2e (build_reject) — `GE[i] = mk()` (an enum-RETURNING CALL RHS) into an ENUM-element ARRAY GLOBAL
## must FAIL LOUD. The literal and enum-VAR RHS forms copy the element's `stride` words into `.data`;
## every other RHS would fall to the width-blind scalar arm, which stores ONE word at `LABEL + i*8` —
## mid-element, a silent miscompile. Bind it to a local first (`t := mk(); GE[i] = t`).
E := enum { N, A(u64) }
mut GE := [E.A(1), E.N]
mk := fn() -> E { E.A(9) }
main := fn() -> u64 {
  GE[0] = mk()
  match GE[0] { E::N => { return 0 } E::A(n) => { return n } }
}
