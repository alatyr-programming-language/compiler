## e2e — Stdlib §2.6, the by-value STRUCT-PARAM half of `agg_cmp_not_address.al`. A struct passed BY
## VALUE arrives by REFERENCE: the callee's frame slot holds the CALLER's block address. On aarch64 /
## riscv64 a bare `a == b` over two such params therefore compared those two ADDRESSES and answered 0
## for two field-EQUAL structs — a silent miscompile that returned 2 here instead of 3. (wat already
## trapped on this shape; a bare struct-LOCAL compare already trapped on all three, which is why the
## PARAM form is what this fixture holds.) x86_64 routes it to the structural `base::derive::eq`; the
## three backends have no structural derive, so the shape must FAIL LOUD there.

P := struct { x : u64, y : u64 }

pcmp := fn(a : P, b : P) -> u64 { if a == b { 1 } else { 0 } }

main := fn() -> u64 {
  ps := P(x = 5, y = 7)
  qs := P(x = 5, y = 7)   ## field-equal with ps, at a DIFFERENT address
  rs := P(x = 5, y = 9)   ## word 0 equal to ps, word 1 different

  mut r := 0
  r = r + pcmp(ps, qs) * 1    ## struct params, equal contents -> +1
  r = r + pcmp(ps, rs) * 64   ## struct params, word 1 differs -> +0
  r = r + 2                   ## 1 + 2 = 3
  return r
}
