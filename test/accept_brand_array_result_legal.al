## e2e — Issue #687, the RUNNING control for the declared fixed-array result sink. Every spelling
## below is the explicit form Types §4.2 prescribes — a result built from `A(...)` at a result
## declared `[A; 2]`, in both the trailing-expression and the early-`return` walker — and all of
## them must stay accepted after the refusal in `test/reject_brand_array_result_sink.al` and
## `test/reject_brand_array_result_return_sink.al` lands.
##
## It is a separate fixture because it has to RUN. The two reject fixtures prove that the refusal
## fires and where; only a program that reaches `main` proves that the newly reachable element walk
## does not refuse a legal result — and `sinks=` on the census channel proves the elements were
## visited and judged clean rather than never looked at (measured: 4 visited, 0 rows).
##
## Neither `mk` nor `rk` is CALLED: a `[A; 2]` result has no return ABI to read it back through, so
## binding or indexing the call result is a located lower trap. They are declared, checked, lowered
## and linked, which is the surface this unit changed; the value `main` returns comes from the
## scalar brand path beside them, so the row is a real `run`, not a compile-only accept.
##
## RUNS to its value on x86_64 only. The three non-x86 backends implement a scalar core that does
## not lower a brand construction at all, so every brand-declaring program in this tree already
## traps loudly there — the same pre-existing backend-subset limit
## `test/accept_brand_unrefused_sinks.al` records, not this unit's doing.
A := brand(u64)

mk := fn() -> [A; 2] { [A(1), A(2)] }
rk := fn() -> [A; 2] { return [A(3), A(4)] }

main := fn() -> u64 {
  a : A = A(9)
  xs : [A; 2] = [A(5), A(3)]
  return u64(a) + u64(xs[0]) + u64(xs[1])
}
