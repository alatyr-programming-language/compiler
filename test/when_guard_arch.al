## e2e — Tooling §2.7 / Comptime §7.1+§9 (CT-5): EVERY backend must (a) fold `target.arch` to the
## machine it is actually emitting FOR, and (b) honour a `when` DECLARATION GUARD. Both used to be
## x86-only: `src/aarch64.al`, `src/riscv64.al` and `src/wat.al` deliberately folded `target.arch` as
## `x86_64` "so the sweep compares like-for-like", so `target.arch == Arch.x86_64` was TRUE while
## emitting aarch64, and none of the three read `Decl.when_cond` at all — so the library could not
## express an arch gate, and `lib/std/thread.al`'s raw x86 GAS `asm(…)` reached `as` verbatim on
## non-x86. This is the regression test for both halves.
##
## (a) ARCH IDENTITY. `on_x86`/`on_a64`/`on_rv` each exist ONLY on the arch its guard names, and `main`
## calls exactly the one for the arch it was compiled for. A backend that named the WRONG arch would
## call a declaration that was DROPPED on this target → an undefined symbol at link (loud), never a
## value. Each body returns the SAME 42 so the corpus `want` is one number on every backend.
##
## (b) `when` HONOURED. `tag` is declared TWICE with COMPLEMENTARY guards; `Arch.i386` is an arch no
## backend here emits, so `!= Arch.i386` is ACTIVE and `== Arch.i386` is DROPPED on every target
## alike. A backend that IGNORED `Decl.when_cond` emits both and fails two ways at once — a DUPLICATE
## `tag` label (verified: the pre-fix aarch64 emit dies at `as` with "symbol `tag' is already
## defined") and an UNDEFINED `absent_on_every_target` at link. Only an honoured guard reaches 42.
##
## WASM is the one target the spec does not name: `Arch := enum { x86_64, i386, aarch64, aarch32,
## riscv32, riscv64 }` (Manifest §3.2, Assembly §10) has no wasm variant — WASM is an ADDITIVE backend
## (FND-6). So on wat every `target.arch == Arch.<variant>` is FALSE, the last `comptime if` fires, and
## the program TRAPS on the absent `arch_identity_unsupported` — the correct conservative outcome for a
## target v1 cannot name, and the reason this fixture is a `run` (x86_64) with a clean trap on wat.
on_x86 := fn() -> u64 when target.arch == Arch.x86_64  { return 42 }
on_a64 := fn() -> u64 when target.arch == Arch.aarch64 { return 42 }
on_rv  := fn() -> u64 when target.arch == Arch.riscv64 { return 42 }

tag := fn() -> u64 when target.arch != Arch.i386 { return 0 }
tag := fn() -> u64 when target.arch == Arch.i386 { return absent_on_every_target() }

main := fn() -> u64 {
  mut r : u64 = 0
  comptime if target.arch == Arch.x86_64  { r = on_x86() }
  comptime if target.arch == Arch.aarch64 { r = on_a64() }
  comptime if target.arch == Arch.riscv64 { r = on_rv() }
  comptime if target.arch != Arch.x86_64 and target.arch != Arch.aarch64 and target.arch != Arch.riscv64 { r = arch_identity_unsupported() }
  return r + tag()
}
