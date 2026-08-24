## P1 signedness: module-global fixed arrays have no SlotEntry, so their declared builtin element type
## must be recovered from the global declaration for `TABLE[i]`. The unsigned globals lock the high-bit
## ordering path; the signed global locks `is_signed_expr` for division (u64::MAX / 2 would not be zero).
mut U : [u64; 2] = [0, 18446744073709551615]
C : [u64; 2] = [18446744073709551615, 0]
S : [i64; 2] = [0 - 1, 0]

main := fn() -> u64 {
  if U[0] < U[1] {
    if C[1] < C[0] {
      if S[0] / 2 == 0 { return 42 }
    }
  }
  1
}
