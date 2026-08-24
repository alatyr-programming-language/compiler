## e2e — Stdlib §2.6: a bare `==` over a by-value ENUM compares CONTENTS — never the block's ADDRESS,
## and never its word-0 DISCRIMINANT alone. x86_64 routes the shape to the structural
## `base::derive::eq`; the wat / aarch64 / riscv64 backends have no structural derive and no working
## injected-generic mono, so the same shape must FAIL LOUD there (`unreachable` / `brk #0` / `ebreak`).
## Before the guard each backend ran to a NORMAL, WRONG exit code — the one forbidden outcome:
##   • wat  — an enum local/param holds a `$__sp` base ADDRESS, so two field-EQUAL blocks read
##            UNEQUAL and this file returned 4.
##   • a64/rv64 — an enum LOCAL's word 0 is only its DISCRIMINANT (so `ea == ec`, same variant with a
##            DIFFERENT payload, read EQUAL) and an enum PARAM's frame slot holds the caller's block
##            ADDRESS (so `ecmp(ea, eb)` read 0): this file returned 69.
## Companion: `agg_cmp_param_not_address.al` (the by-value STRUCT-param half, which wat already
## trapped on). A TUPLE / fixed-ARRAY compare is deliberately absent — x86_64 itself still compares
## word 0 ONLY there (`[5,7] == [5,9]` reads EQUAL), and a fixture must not lock that bug in.

E := enum { A(u64), B(u64) }

## by-value enum PARAMS — the shape whose frame slot carries a base address on a64/rv64
ecmp := fn(a : E, b : E) -> u64 { if a == b { 1 } else { 0 } }

main := fn() -> u64 {
  ea := E.A(5)
  eb := E.A(5)            ## field-equal with ea, at a DIFFERENT address
  ec := E.A(9)            ## SAME variant as ea, different payload

  mut r := 0
  if ea == eb { r = r + 1 }     ## enum locals, equal contents             -> +1
  if ea == ec { r = r + 64 }    ## enum locals, same disc, payload differs -> +0
  r = r + ecmp(ea, eb) * 2      ## enum params, equal contents             -> +2
  r = r + ecmp(ea, ec) * 64     ## enum params, payload differs            -> +0
  r = r + 4                     ## 1 + 2 + 4 = 7
  return r
}
