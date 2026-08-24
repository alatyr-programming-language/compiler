## e2e — COMPTIME `when` DECLARATION-GUARD on a `struct` TYPE decl (`NAME := struct { … } when …`,
## Comptime §7.1/§9, CT-5). The parser now parses a trailing `when <predicate>` after the struct
## body's `}` and sets `Decl.when_cond`; the existing kind-agnostic Phase-B fold drops the whole
## type decl (fields and all) when the CLOSED target predicate folds FALSE.
##
## OBSERVABLE via layout: a duplicate struct name resolves to the LAST decl (verified), so the
## FALSE-guarded 5-field `Cfg` (40 bytes) is declared LAST. On this x86_64 build it folds FALSE
## (`Arch.aarch64`) and is DROPPED, leaving only the TRUE 2-field `Cfg` (16 bytes, `Arch.x86_64`,
## first). `Cfg.size()` is then 16 → 16 + 26 = 42. If the guard were ignored, last-match would pick
## the 5-field struct → 40 + 26 = 66 (verified). Proves both DROP (false) and KEEP (true).
Cfg := struct { a : u64, b : u64 } when target.arch == Arch.x86_64
Cfg := struct { a : u64, b : u64, c : u64, d : u64, e : u64 } when target.arch == Arch.aarch64

main := fn() -> u64 {
  Cfg.size() + 26
}
