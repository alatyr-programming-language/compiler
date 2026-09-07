## Issue #507 / Declarations §5 + §7.2 — the `while` condition carried NO name-resolution prepass at
## all, so an undeclared comparison operand slipped there too and the arbitrary answer was "enter the
## loop". `vv` is a local of the sibling function `owner` and is visible in neither `user` nor
## anywhere else.
##
## On the parent compiler this BUILT CLEAN, `user` entered the loop, and only the planted guard
## `k > 5` stopped it, so the program exited 99. Must be REFUSED by `check`, located at the operand.
owner := fn() -> u64 { mut vv := 0  while vv < 3 { vv = vv + 1 }  vv }
user := fn(x : u64) -> u64 { mut k := 0  while vv < 3 { k = k + 1  if k > 5 { return 99 } }  40 + k }
main := fn() -> u64 { if owner() != 3 { return 50 }  user(2) }
