## e2e — COMPTIME `when` DECLARATION-GUARD on a TYPE-ANNOTATED binding (`NAME : T = v when …`,
## Comptime §7.1/§9, CT-5). Companion of `when_guard` (which covers fn + inferred-binding forms):
## here the guard rides a top-level `K : u64 = <value>` typed binding — the parser parses the trailing
## `when <predicate>` on that form and sets `Decl.when_cond`, so the Phase-B fold drops the decl when
## its CLOSED target predicate folds FALSE.
##
## OBSERVABLE: a duplicate module const resolves to the LAST decl of that name. Each target declares
## its own `val`, and `main` checks the value of the target it was compiled for, so the program answers
## 42 on every backend when — and only when — the guards fold: if they were ignored, last-match would
## pick the final declaration's 9 everywhere and every target but wasm would return its failure code.
## (It used to answer 42 on x86_64 and its designed 100 on aarch64, which the cross-backend counter
## correctly could not tell from a wrong value; owner decision 2026-10-15: make the fixture
## target-neutral rather than declare target-defined rows.) wasm has no `Arch` variant (FND-6), so it
## takes the declaration none of the three named architectures selects.
val : u64 = 42 when target.arch == Arch.x86_64
val : u64 = 100 when target.arch == Arch.aarch64
val : u64 = 7 when target.arch == Arch.riscv64
val : u64 = 9 when target.arch != Arch.x86_64 and target.arch != Arch.aarch64 and target.arch != Arch.riscv64

main := fn() -> u64 {
  comptime if target.arch == Arch.x86_64 { if val != 42 { return 1 } }
  comptime if target.arch == Arch.aarch64 { if val != 100 { return 2 } }
  comptime if target.arch == Arch.riscv64 { if val != 7 { return 3 } }
  comptime if target.arch != Arch.x86_64 and target.arch != Arch.aarch64 and target.arch != Arch.riscv64 { if val != 9 { return 4 } }
  42
}
## expect: run 42
