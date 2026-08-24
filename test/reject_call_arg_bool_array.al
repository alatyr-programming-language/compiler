## TYP-6 / Types §9.4 — the same one-word-literal-into-an-N-word-aggregate judgement for a BOOLEAN
## literal. `f(true)` built clean and SIGSEGV'd (the discriminant 1 used as the array's address).
f := fn(xs : [u64; 2]) -> u64 { return xs[0] }

main := fn() -> u64 { return f(true) }
