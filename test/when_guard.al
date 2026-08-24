## e2e — COMPTIME `when` DECLARATION-GUARD (Comptime §7.1/§9, CT-5). `when <comptime-predicate>` gates
## a declaration's EXISTENCE: a decl whose CLOSED (target-gating) predicate folds FALSE is parsed but
## then NOT name-resolved / type-checked / emitted — it is "as if absent" (the two-phase rule §9).
##
## Two COMPANION `answer` fns carry COMPLEMENTARY target guards. On this x86_64 build the
## `when target.arch == Arch.x86_64` decl is ACTIVE (returns 42); the `when target.arch == Arch.aarch64`
## decl folds FALSE and is DROPPED before emission. Its body CALLS a nonexistent `absent_on_x86()`, so
## if the guard were ignored the build would fail two ways at once — a DUPLICATE `answer` label
## (the assembler rejects it) and an UNDEFINED-symbol link error. It builds+links+runs cleanly to 42,
## proving the false-guarded decl is genuinely excluded (Phase B): neither its duplicate definition nor
## its dangling call reaches the backend.
##
## Plus a gated inferred CONSTANT (the `:= … when …` binding-tail form): the FALSE `Arch.riscv64` decl
## (declared FIRST, value 100) is dropped and the TRUE `Arch.x86_64` decl (value 0) stays, so the name
## `bonus` resolves to 0 — `answer() + bonus` = 42, not 142 (which an un-dropped first `bonus` would give).
answer := fn() -> u64 when target.arch == Arch.x86_64 { return 42 }
answer := fn() -> u64 when target.arch == Arch.aarch64 { return absent_on_x86() }

bonus := 100 when target.arch == Arch.riscv64
bonus := 0 when target.arch == Arch.x86_64

main := fn() -> u64 {
  answer() + bonus
}
