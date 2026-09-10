## Issue #580 — a `::` HEAD THAT NAMES NOTHING must be a located compile error.
##
## Measured on the parent (`origin/main` 73a6632, x86_64, `nix develop`, `ulimit -c 0`): this file
## BUILT at rc 0 and the artifact RAN to 7 — the head was ignored and the call bound to the root's
## own `aa`. A wrong answer to a typo: the user names one thing and gets another, with no
## diagnostic at all. Every resolver in the tree matches a qualified callee by its TAIL segment
## alone, so nothing ever read `zzz`.
##
## The refusal is the owner's rule on #580: a non-existent, non-external name must produce a clear
## compile error. Deliberately the LAST declaration order-independently: the verdict is reported at
## the end of `check`, so it cannot depend on whether `zzz` might have been declared later.
aa := fn() -> u64 { 7 }

main := fn() -> u64 {
  zzz::aa()
}
