## Issue #1734 / Modules §4.1, Types §4.1 — a call through an import alias (`mk := m::mk`) reaches
## `m`'s declaration, and the alias is erased: the callee's `-> S` is `m`'s `S`, a nominal type of its
## own, even though the calling module declares a different `S` with `a` at another offset. The result
## is read by value off a bound local, off the call itself, and passed on to another aliased callee.
## Answers 10 + 1 + 21 + 10 = 42.
##
## Base `b74089f3` (omen): x86_64 exits 71, not 42, because the caller's `S` laid out `m`'s result.
## aarch64 and riscv64 trap with 133 and wasm with 134: the twins do not call through a named
## function alias at all (#1740). A caller `S` that lacks the field is refused at check instead (the
## sema half, `issue1734_alias_callee_agg_result_check`).
app := Package(
  version = "0.1.0",
  source_dir = "src",
  target_dir = "target",
  targets = [
    Target(
      arch = Arch.x86_64,
      os = Os.linux,
      env = Env.gnu,
      container = Container.elf,
      kind = Kind.executable,
      output = "issue1734-alias-callee-agg-result",
    ),
  ],
)
## expect: run 42
