## Issue #507 / Declarations §5 + §7.2 — an UNDECLARED name used as an OPERAND of a comparison inside
## an `if` condition. `vv` is a local of the SIBLING function `owner`; Declarations §5 makes scope
## lexical and block-structured ("a name is visible in the scope where it is declared and in all
## nested scopes") and §7.2 makes a local visible only "from its point of declaration onward", so it
## is visible in neither `user` nor anywhere else, and this program is ill-formed.
##
## On the parent compiler this BUILT CLEAN and `user` took the `return 22` branch — the condition
## answered TRUE off a read of a frame word the function does not have — so the program exited 62.
## The sibling spelling and the declared-nowhere spelling (issue507_if_cond_operand_unbound_absent)
## take OPPOSITE branches on the parent, 62 against 73, which is what proves a garbage read rather
## than a stable `false`. Must be REFUSED by `check`, located at the operand.
Rec := struct { ek : u64 }
owner := fn() -> u64 { vv := Rec(ek = 4)  vv.ek }
user := fn(x : u64) -> u64 { if vv.ek == 4 { return 22 }  33 }
main := fn() -> u64 { if owner() != 4 { return 50 }  40 + user(2) }
