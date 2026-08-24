## §5.1: a call may omit only trailing params that ALL carry a default. Here `b` has NO default, so
## `need(1)` (which binds `a` positionally and omits `b`) is a genuine arity error and MUST be rejected —
## the default on the EARLIER param `a` does not license omitting the later non-defaulted `b`.
need := fn(a : u64 = 1, b : u64) -> u64 { a + b }
main := fn() -> u64 { need(1) }
