## e2e — #1578, Tooling §2.7 / Comptime §9.2: `target.*` is the SELECTED Target, and a twin emit verb
## selects the machine it emits for. `alatyr aarch64 <file>` published nothing, so sema and the shared
## `lower::ctfold` reader both answered x86_64 while the emitter answered `aarch64` from a private
## constant; the `comptime if` fold on the twin read only `target.arch`.
##
## (a) A `when`-guarded pair: exactly one `part` exists on every target. Sema keeps the alternative the
## published model selects, and the twin's lowering drops the other one by the same model; two kept, or
## none, is a duplicate label or an undefined symbol.
## (b) `comptime if` on `target.os` and `target.env`, folded at lowering from the published model. On an
## ISA target the per-arch appendix §1 row decides them: os linux on every Linux row the backends
## emit; env gnu or musl on x86_64 and aarch64 (which one is the implementation-derived
## `‹arch-default›`, Manifest appendix §3.1/§3.7, so the fixture accepts either) and gnu alone on
## riscv64. A non-ISA backend (wat) matches no `Arch` variant (Tooling §2.7), and its `os`/`env` are
## unspecified at pin 1.9.0 (spec#143), so this fixture asserts nothing about them there: the outer
## arm adds the same 22.
##
## PARENT (cf159743), measured on native x86_64: `alatyr aarch64` emitted, assembled and linked with
## rc 0, and the program ran under qemu-aarch64 to exit 133 (SIGTRAP) where 42 was due, because the
## twin's `comptime if` could not fold `target.os` / `target.env`. `alatyr riscv64` the same, 133
## under qemu-riscv64, and still 133 on the parent of the riscv64 leg (696f9b12, the aarch64 leg).
## x86_64 (`alatyr run`) and wat ran to 42.
part := fn() -> u64 when target.arch == Arch.aarch64 { return 20 }
part := fn() -> u64 when target.arch != Arch.aarch64 { return 20 }

main := fn() -> u64 {
  mut x : u64 = part()
  comptime if target.arch == Arch.x86_64 or target.arch == Arch.aarch64 or target.arch == Arch.riscv64 {
    comptime if target.os == Os.linux { x = x + 10 } else { x = x + 100 }
    comptime if target.env == Env.gnu or target.env == Env.musl { x = x + 12 } else { x = x + 100 }
  } else {
    x = x + 22
  }
  return x
}
## expect: run 42
