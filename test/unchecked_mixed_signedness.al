## e2e — Types §4.2/§4.3: a `u64` and an `i64` operand of one operator are ill-formed, `unchecked` or not.
## A signed<->unsigned change is a NUMERIC conversion, always explicit, and no operator takes an `iN`
## and a `uM` (§4.5). `unchecked` changes what an operation does on overflow (CG-7), never which
## operations exist, so `unchecked (w + k)` is refused exactly as `w + k` is.
##
## History: this program used to RUN, and pinned the x86 `unchecked` type peel to one answer for both
## operand orders (`infer_local_scalar_type` took the FIRST typed operand, so `u64 + i64` read as
## unsigned and `i64 + u64` as signed). The check now refuses the pair before any backend sees it, so
## the order question cannot be written; the last line keeps the proven `u64 + u64` peel visible.
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
