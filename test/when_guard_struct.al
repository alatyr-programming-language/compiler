## e2e — COMPTIME `when` DECLARATION-GUARD on a `struct` TYPE decl (`NAME := struct { … } when …`,
## Comptime §7.1/§9, CT-5). The parser parses a trailing `when <predicate>` after the struct body's `}`
## and sets `Decl.when_cond`; the kind-agnostic Phase-B fold drops the whole type decl (fields and all)
## when the CLOSED target predicate folds FALSE.
##
## OBSERVABLE via layout: a duplicate struct name resolves to the LAST decl. Each architecture keeps a
## 2-field `Cfg` (16 bytes) of its own, and the LAST declaration is a 5-field `Cfg` (40 bytes) guarded by
## `Arch.i386`, which none of these targets is. `Cfg.size()` is then 16 → 16 + 26 = 42 on every target
## that folds its guards; ignoring them would leave the last, 40-byte `Cfg` → 66. Proves DROP (false)
## and KEEP (true) on each backend.
## (Target-neutral since 2026-10-15, owner decision: it used to declare a 40-byte `Cfg` for aarch64, so
## aarch64 answered its designed 66, which the cross-backend counter could not tell from a wrong value.)
## wasm has no `Arch` variant (FND-6), so no `Cfg` is declared for it and it refuses, loudly.
Cfg := struct { a : u64, b : u64 } when target.arch == Arch.x86_64
Cfg := struct { p : u64, q : u64 } when target.arch == Arch.aarch64
Cfg := struct { r : u64, s : u64 } when target.arch == Arch.riscv64
Cfg := struct { a : u64, b : u64, c : u64, d : u64, e : u64 } when target.arch == Arch.i386

main := fn() -> u64 {
  Cfg.size() + 26
}
