## e2e (COMPTIME-IF evaluation — the first piece of the comptime evaluator). `comptime if <cond>
## { then } else { else }` is now PARSED into a `Stmt::CompIf` node (was consumed as a no-op) and
## the condition is FOLDED at compile time: an `arch`/`verify` predicate emits ONLY the taken branch.
##
## ARCH-NEUTRAL by construction (Tooling §2.7). `target.*` is the RESOLVED SELECTED machine model, so
## every backend folds `target.arch` to the machine IT is emitting for — this file used to hard-code
## the x86_64 answer (`== Arch.x86_64` then-branch + `== Arch.aarch64` else-branch), which made its
## value 1998, not 42, the moment the aarch64/riscv64/wat backends stopped pretending to be x86_64.
## The predicates below name `Arch.i386` instead — an arch NO backend in this corpus emits — so
## `== Arch.i386` is FALSE and `!= Arch.i386` TRUE on every target alike: `pick` exercises the ELSE
## branch, `other` the THEN branch, and the sum is 42 wherever it is compiled. A fold that took the
## wrong branch yields 1998 (999 + 999), and one that emitted NEITHER branch falls through the fn.
## (WHICH arch each backend names is pinned separately by `when_guard_arch`.)
pick := fn() -> u64 {
  comptime if target.arch == Arch.i386 { return 999 } else { return 40 }
}
other := fn() -> u64 {
  comptime if target.arch != Arch.i386 { return 2 } else { return 999 }
}
main := fn() -> u64 {
  pick() + other()
}
