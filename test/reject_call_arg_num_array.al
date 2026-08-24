## TYP-6 / Types §9.4 — the MIRROR of `reject_call_arg_array_num`: a bare integer literal against a
## fixed-ARRAY parameter. §3.4's "a literal takes its type from context" governs the numeric TYPE the
## literal takes (`u8` vs `u64`), never whether it becomes an N-element aggregate — so there is no
## conforming reading. An array parameter is passed BY REFERENCE, so `f(7)` passed the VALUE 7 as the
## aggregate's address: it built clean and SIGSEGV'd on the first element read.
f := fn(xs : [u64; 2]) -> u64 { return xs[0] }

main := fn() -> u64 { return f(7) }
