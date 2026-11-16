## e2e — #1711: a NICHE-FOLDED `Option(ptr(T))` whose enum declares `Some` FIRST (as the compiler's own
## `src/ast.al` does) is the same one pointer word as the prelude's, with no discriminant (Types §6.2:
## the single extra variant folds into the payload's niche whatever its position). `None` is the null
## pattern (0) and `Some(p)` the pointer `p`, so a variant is tested by its MEANING — `None` is
## `word == 0`, `Some` is `word != 0` — never by its discriminant, which here is 0 for `Some`.
## Covered: a parameter, a result, a local, a `match` with each arm order, and a call across the
## IR-built / legacy-built boundary in both directions (`?` is `test/package/ir1711_some_first_try`). `lg_rd`
## and `lg_pass` hold a float literal the IR does not build, so the legacy emitter emits them; `rd`, `rd_none_first`, `mk` and `main` are IR-built (`alatyr ir`):
##   * IR -> legacy: `main` calls `lg_rd` / `lg_pass`;
##   * legacy -> IR: `lg_pass` passes a folded value to `rd`, an IR-built callee.
## On the PARENT every function with a folded signature was refused by the builder (`signature:
## parameter type names no struct or enum resolvable here`), and the whole program went to the legacy
## emitter (x86_64 42, aarch64 and riscv64 42, wasm 134: measured, the same on the head). The
## directive names the backends that answer 42: aarch64 and riscv64 keep a folded
## signature on their legacy emitter (`ir::sig_pins_legacy`), and wasm is left undeclared as the
## whole folded-option family leaves it (its legacy emitter traps on a folded local).
## Each check answers its own code, 101 upward, when it fails; 42 when all held.
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
      output = "ir1711-cross",
    ),
  ],
)
## expect(x86_64): run 42
## expect(aarch64): run 42
## expect(riscv64): run 42
