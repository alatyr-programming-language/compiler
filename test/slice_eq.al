## e2e — Stdlib §2.6 / Types §6.4: a bare `==` / `!=` over a `Slice(T)` VIEW compares its CONTENT,
## never the `{ptr, len}` pair's IDENTITY and never the block ADDRESS.
##
## Three distinct silent wrong values lived here, all normal-exit (the one forbidden outcome):
##   (1) a slice LOCAL fell to the scalar `cmpq` and compared WORD 0 — the DATA POINTER. Two views
##       over EQUAL contents at different addresses read UNEQUAL; two views of the SAME buffer with
##       DIFFERENT lengths read EQUAL; two EMPTY views over different bases read UNEQUAL.
##   (2) a slice PARAM was worse than word 0 — its slot holds a POINTER to the caller's {ptr,len}
##       block, so the compare answered on two BLOCK ADDRESSES (the slice twin of
##       `agg_cmp_param_not_address`). It also failed to BUILD: the mono pre-pass registered a dead
##       `derive::eq(Slice(u64))` whose recursion emitted the label `base__derive__eq__ptr(T)`.
##   (3) a slice EXPRESSION (`xs[0..3] == ys[0..3]`) was intercepted by the `str` route —
##       `is_str_operand` accepts every `Expr::Slice` — which BYTE-compares `len` bytes. A typed
##       slice's `len` counts ELEMENTS, so `[1,2,3]` vs `[1,9,3]` compared three bytes of word 0 and
##       read EQUAL.
##
## Covers: equal contents at DIFFERENT addresses, the same base at DIFFERENT lengths, a word-1-only
## difference, `!=`, slice EXPRESSIONS on both sides, two EMPTY views, and by-reference slice PARAMS.
## 1 + 2 + 4 + 8 + 16 + 3 + 5 + 3 = 42.
##
## `str` is untouched by this route (a str local is a str slot; a str sub-view has no array base), so
## its byte compare — whose `len` really IS a byte count — still owns those. The wat / aarch64 /
## riscv64 backends reject a bare slice comparison loudly, so this fixture traps there.
sl_eq := fn(p : Slice(u64), q : Slice(u64)) -> bool { return p == q }
sl_ne := fn(p : Slice(u64), q : Slice(u64)) -> bool { return p != q }
main := fn() -> u64 {
  xs : [u64; 3] = [1, 2, 3]
  ys : [u64; 3] = [1, 2, 3]        ## equal to `xs` by VALUE, at a different address
  zs : [u64; 3] = [1, 9, 3]        ## differs from `xs` in WORD 1 only
  a := xs[0..3]
  b := ys[0..3]
  c := xs[0..2]                    ## the SAME base as `a`, a shorter length
  d := zs[0..3]
  mut acc : u64 = 0
  if a == b { acc = acc + 1 } else { acc = acc + 100 }        ## value, not address     -> +1
  if a == c { acc = acc + 100 } else { acc = acc + 2 }        ## length is compared     -> +2
  if a != d { acc = acc + 4 } else { acc = acc + 100 }        ## word-1 difference seen -> +4
  if xs[0..3] == ys[0..3] { acc = acc + 8 } else { acc = acc + 100 }   ## EXPRESSIONS   -> +8
  if xs[0..3] == zs[0..3] { acc = acc + 100 } else { acc = acc + 16 }  ## elements, not bytes -> +16
  e0 := xs[0..0]
  e1 := ys[0..0]
  if e0 == e1 { acc = acc + 3 } else { acc = acc + 100 }      ## two EMPTY views        -> +3
  if sl_eq(a, b) { acc = acc + 5 } else { acc = acc + 100 }   ## by-ref slice PARAMS    -> +5
  if sl_ne(a, d) { acc = acc + 3 } else { acc = acc + 100 }   ## `!=` through params    -> +3
  return acc
}
