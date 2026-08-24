## TYP-6 / Types §9.4 — a fixed-ARRAY literal argument against a word-sized integer parameter. An
## `[e0, …, eN]` literal is an N-element aggregate; no conversion-lattice class relates it to `u64`.
## `f([1, 2])` built and returned the aggregate's first word (56, then whatever the frame held).
f := fn(n : u64) -> u64 { return n }

main := fn() -> u64 { return f([1, 2]) }
