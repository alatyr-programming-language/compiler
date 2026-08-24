## e2e — Verification § / D70/D82: the `unchecked` type peel is PROOF-ONLY, so it must not depend on
## OPERAND ORDER, and a pair containing a provably SIGNED member proves nothing.
##
## What was wrong: `lower::infer_local_scalar_type`'s `Bin` arm recorded the FIRST TYPED operand, so
## a `u64 + i64` pair recorded `u64` — moving the result signed -> unsigned WITHOUT proof. The same
## program with the operands flipped recorded `i64`, which `unsigned_ty_only` filters out, leaving
## the always-signed default. Measured on the pre-fix compiler, with `w : u64` above 2^63:
##
##   s := unchecked (w + k) ; s < w   -> 3   (treated UNSIGNED)
##   s := unchecked (k + w) ; s < w   -> 4   (treated SIGNED)
##
## Same program, operand order flipped, different answer — and only one of the two could be right.
## The three non-x86 backends already require BOTH operands proven and answered the SIGNED reading
## for both orders; x86 now agrees, in the sound direction (it can only record a type the pair
## actually proves).
##
## Covers: BOTH operand orders of a mixed-signedness pair (which must agree with each other), and the
## PROVEN `u64 + u64` pair, which must still keep its unsignedness — the peel this tightening must
## not undo. 20 + 20 + 2 = 42, and the same 42 on aarch64, riscv64 and wasm.
main := fn() -> u64 {
  w : u64 = 18446744073709551610
  k : i64 = 6
  d : u64 = 6
  mut acc : u64 = 0
  a := unchecked (w + k)           ## unsigned operand FIRST
  b := unchecked (k + w)           ## signed operand FIRST — the SAME pair
  if a < w { acc = acc + 100 } else { acc = acc + 20 }   ## neither pair proves unsignedness -> +20
  if b < w { acc = acc + 100 } else { acc = acc + 20 }   ## and the flipped order agrees     -> +20
  s := unchecked (w + d)           ## BOTH operands proven unsigned
  if s < w { acc = acc + 2 } else { acc = acc + 100 }    ## the peel still fires             -> +2
  return acc
}
