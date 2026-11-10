## e2e — #1578, Tooling §2.7 / Comptime §9.2: `target.*` is the SELECTED Target, and a twin emit verb
## selects the machine it emits for. `alatyr aarch64 <file>` published nothing, so sema and the shared
## `lower::ctfold` reader both answered x86_64 while the emitter answered `aarch64` from a private
## constant; the `comptime if` fold on the twin read only `target.arch`.
##
## (a) A `when`-guarded pair: exactly one `part` exists on every target. Sema keeps the alternative the
## published model selects, and the twin's lowering drops the other one by the same model; two kept, or
## none, is a duplicate label or an undefined symbol.
## (b) `comptime if` on `target.os` and `target.env`, folded at lowering from the published model. On an
## ISA target both are decided by the per-arch appendix §1 row (linux / gnu for every Linux row the
## backends emit). A non-ISA backend (wat) matches no `Arch` variant (Tooling §2.7), and its `os`/`env`
## are unspecified at pin 1.9.0, so this fixture asserts nothing about them there: the outer arm adds
## the same 22.
##
## PARENT (cdcecb5c), `alatyr aarch64`, measured on native x86_64 under qemu-aarch64: compiled,
## assembled and linked with rc 0, then ran to exit 133 (SIGTRAP) where 42 was due. The emitted
## assembly held 2 `brk #0` sites, one for the `target.os` fold and one for the `target.env` fold, which
## the twin could not decide. x86_64 and wat ran to 42 on the parent; riscv64 trapped the same way (133),
## and its leg of #1578 follows this one.
part := fn() -> u64 when target.arch == Arch.aarch64 { return 20 }
part := fn() -> u64 when target.arch != Arch.aarch64 { return 20 }

main := fn() -> u64 {
  mut x : u64 = part()
  comptime if target.arch == Arch.x86_64 or target.arch == Arch.aarch64 or target.arch == Arch.riscv64 {
    comptime if target.os == Os.linux { x = x + 10 } else { x = x + 100 }
    comptime if target.env == Env.gnu { x = x + 12 } else { x = x + 100 }
  } else {
    x = x + 22
  }
  return x
}
## expect: run 42
