## Issue #507 — a row the issue's boundary table did not reach: because the `while` condition ran NO
## name-resolution prepass, not even a BARE undeclared name as the WHOLE condition was refused there,
## while the `if` form of the same shape (issue507_if_cond_bare_unbound_control) already was. The
## parent BUILT THIS CLEAN and exited 7 — the loop was not entered, but that answer came from a read
## of a place `main` does not have, not from a decision. Declarations §5 + §7.2: ill-formed, and the
## `while` condition must now produce the same located refusal the `if` condition does.
main := fn() -> u64 { while vv { return 1 }  7 }
