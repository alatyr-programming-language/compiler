## e2e reject — issue #469, the ORDERING half. `<` `>` `<=` `>=` over a payload-carrying enum needs
## `base::derive::lt`'s enum arm, whose statement-form `comptime for v in typeinfo(T).variants`
## emit does not exist yet; the routing has refused it for two enum LOCALS since the aggregate
## comparison was introduced. A CONSTRUCTOR operand never reached that refusal: the operand
## classification read a frame SLOT and answered non-zero only for a `Var`, so the whole comparison
## fell through to the scalar path and materialized each multi-word operand as the constant `$0`.
##
## The parent therefore BUILT this program with no diagnostic and answered `Pay.B(1,1) < Pay.B(2,2)`
## as "not less" — a silent wrong ordering (measured 42 on 495cc51, i.e. the else arm). Now the
## operand is classified, the comparison reaches the same refusal two enum locals get, and the
## build stops with a located message that names the operator class and the unimplemented derive arm.
##
## AGENTS.md: a trap or a located reject is acceptable, a wrong value is not. When the ordering emit
## lands this fixture becomes a `run` row.

Pay := enum { A(u64), B(u64, u64) }

main := fn() -> u64 {
  if Pay.B(1, 1) < Pay.B(2, 2) { return 41 }
  return 42
}
