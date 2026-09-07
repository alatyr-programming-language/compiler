## Issue #507 / Declarations §5 + §7.2 — the SAME walk, in the position it was written for: a
## discarded expression statement. `expr_statement_has_unbound`'s `Bin` arm answered "clean" here too,
## so `vv + 1` with `vv` declared nowhere BUILT CLEAN on the parent (the program exited 7). A
## discarded value still names a place, and Declarations §5 + §7.2 give it none. Must be REFUSED by
## `check`, located at the operand. This is a reject, so it never runs and cannot record a value.
main := fn() -> u64 { vv + 1  7 }
