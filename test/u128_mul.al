## e2e part 2, TYP-10 slice C: MULTIPLY (`*`) on the prelude `u128 ≡ uint(128)`
## (Types §3/§7, TYP-2 / TYP-10; operators.md OP-1). `@inline` GENERIC schoolbook
## multiply over the comptime value parameter N (lib/base/u128.al), keeping the LOW N bits: column
## k sums the low halves of `a[i]·b[j]` (i+j=k), the high halves (i+j=k-1), and the incoming carry;
## the per-word high half is the x86_64 `mulq`→`%rdx` synthetic `mulhiq` INLINED in the operator
## body (a comptime-param helper fn is not declarable). All adds wrap (`unchecked` = the modular
## reduction). (Operands are bound to LOCALS — an operator over struct LITERALS is a separate
## front-end gap: `expr_type_span` can't infer a StructLit operand's type, so the route needs a
## typed variable.)
##
## Cases force a carry ACROSS the word boundary and through the cross terms:
##   [2^32, 0] * [2^32, 0] = [0, 1]   — low product 2^64 wraps, the mulhiq high half lands in word 1
##   [0, 3]    * [5, 0]    = [0, 15]  — cross term a[1]·b[0] = 15 lands in word 1
##   [6, 0]    * [4, 0]    = [24, 0]  — plain low product
##   [2, 0]    * [1, 0]    = [2, 0]   — plain low product
## 42 = p.w1 + q.w1 + r.w0 + s.w0 = 1 + 15 + 24 + 2. A dropped mulhiq carry -> p.w1=0 (41);
## a dropped cross term -> q.w1=0 (27). Only the full schoolbook recipe yields 42.
main := fn() -> u64 {
  a := u128(words = [4294967296, 0])
  b := u128(words = [4294967296, 0])
  p := a * b

  c := u128(words = [0, 3])
  d := u128(words = [5, 0])
  q := c * d

  e := u128(words = [6, 0])
  f := u128(words = [4, 0])
  r := e * f

  g := u128(words = [2, 0])
  h := u128(words = [1, 0])
  s := g * h

  return p.words[1] + q.words[1] + r.words[0] + s.words[0]
}
