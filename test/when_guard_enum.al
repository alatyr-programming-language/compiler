## e2e — COMPTIME `when` DECLARATION-GUARD on an `enum` TYPE decl (`NAME := enum { … } when …`,
## Comptime §7.1/§9, CT-5). The parser now parses a trailing `when <predicate>` after the enum
## body's `}` and sets `Decl.when_cond`; the same kind-agnostic Phase-B fold drops the whole enum
## decl when the CLOSED target predicate folds FALSE.
##
## On this x86_64 build the FALSE-guarded `Sh` (`Arch.aarch64`, declared LAST) is DROPPED before
## name-resolution/emission — the program still builds+links+runs because the TRUE-guarded `Sh`
## (`Arch.x86_64`, first) provides the name and its `Answer(u64)` payload. `main` constructs
## `Sh.Answer(42)` and matches → 42. (Enum variant resolution is name/arity-based rather than a
## bare last-match, so the observable here is the clean build+run with the false-guarded enum
## excluded and the true-guarded one used, not a numeric flip.)
Sh := enum { Answer(u64), Other } when target.arch == Arch.x86_64
Sh := enum { Other } when target.arch == Arch.aarch64

main := fn() -> u64 {
  s := Sh.Answer(42)
  match s {
    Sh.Answer(v) => v,
    Sh.Other => 0
  }
}
