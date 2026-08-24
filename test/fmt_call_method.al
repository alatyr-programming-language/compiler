## fmt — the ROOT fix for the call-then-member vs generic-enum-ctor ambiguity (§5 tooling). The fmt
## driver now runs a two-pass enum-name pre-scan (like build/check), so the parser's
## `is_generic_enum_ctor` defers to `is_enum_name`: a plain call-then-member `f(args).member` parses as
## a Call + Field/UFCS with its ARGUMENTS PRESERVED, instead of being mistaken for a generic-enum ctor
## `E(T).V` (which dropped the args). This locks the variant the old fmt.al source-scan workaround did
## NOT cover: a call-then-METHOD-with-args `mk(7).bump(3)` (UFCS on a call receiver), alongside the
## call-then-field `mk(20).v`. Formats idempotently + runs 42:
##   a = mk(20).v = 20 ; b = mk(7).bump(3) = 7+3 = 10 ; c = mk(4).v + mk(6).bump(2) = 4+8 = 12 ; 20+10+12 = 42.
P := struct { v : u64 }
mk := fn(n : u64) -> P { return P(v = n) }
bump := fn(in p : P, k : u64) -> u64 { return p.v + k }
main := fn() -> u64 {
  a := mk(20).v
  b := mk(7).bump(3)
  c := mk(4).v + mk(6).bump(2)
  return a + b + c
}
