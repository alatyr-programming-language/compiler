## e2e — #1711: `?` on a NICHE-FOLDED `Option(ptr(T))` whose enum declares `Some` FIRST, in a function
## whose result is folded too. The operand has no tag word (Types §6.2): its success test is the
## variant's meaning (`Some` is `word != 0`, though `Some` is discriminant 0 here), its payload is the
## one word, and the absent result is the null pattern, with no discriminant stored into it. `fwd`
## is IR-built (`alatyr ir`); on the PARENT its signature was refused (`signature: parameter type
## names no struct or enum resolvable here`). The prelude's None-first order is
## `test/ir_option_ptr_try.al`.
## Only x86_64 is declared: aarch64 and riscv64 keep a folded signature on their legacy emitter
## (`ir::sig_pins_legacy`), which traps (133) on `?` over a folded option on the parent and the head
## alike, and wasm is left undeclared as the whole folded-option family leaves it.
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
      output = "ir1711-try",
    ),
  ],
)
## expect(x86_64): run 42
