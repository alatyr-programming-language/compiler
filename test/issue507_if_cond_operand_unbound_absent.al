## Issue #507 / Declarations §5 + §7.2 — the same missed position as
## issue507_if_cond_operand_unbound_sibling, with `vv` declared NOWHERE in the program. That is what
## rules out "a name leaked across function scopes" as the explanation: there is no `vv` to leak.
##
## On the parent compiler this BUILT CLEAN and the condition answered FALSE, so `user` fell through to
## `33` and the program exited 73 — the OPPOSITE branch from the sibling spelling's 62. Two spellings
## that differ only in whether a same-named local exists elsewhere must not choose different branches;
## both are ill-formed and must be REFUSED by `check`, located at the operand.
Rec := struct { ek : u64 }
user := fn(x : u64) -> u64 { if vv.ek == 4 { return 22 }  33 }
main := fn() -> u64 { 40 + user(2) }
