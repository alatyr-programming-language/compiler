## e2e — COMPTIME `when` DECLARATION-GUARD on a TYPE-ANNOTATED binding (`NAME : T = v when …`,
## Comptime §7.1/§9, CT-5). Companion of `when_guard` (which covers fn + inferred-binding forms):
## here the guard rides a top-level `K : u64 = <value>` typed binding — the parser now parses the
## trailing `when <predicate>` on that form and sets `Decl.when_cond`, so the existing Phase-B fold
## drops the decl when its CLOSED target predicate folds FALSE.
##
## OBSERVABLE: a duplicate module const resolves to the LAST decl of that name, so the FALSE-guarded
## `val = 100` is declared LAST. On this x86_64 build it folds FALSE (`Arch.aarch64`) and is DROPPED
## before name-resolution, leaving only the TRUE `val = 42` (`Arch.x86_64`, declared first) → `main`
## returns 42. If the guard were ignored, last-match would pick `val = 100` (verified) → 100.
val : u64 = 42 when target.arch == Arch.x86_64
val : u64 = 100 when target.arch == Arch.aarch64

main := fn() -> u64 {
  val
}
