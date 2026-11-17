## e2e — #1711: a NICHE-FOLDED `Option(ptr(T))` LOCAL whose enum declares `Some` FIRST, read with
## `match` in each arm order, in a program whose signatures mention NO folded option, so `main` is
## IR-built on every backend (a folded signature is pinned to the legacy emitter on aarch64, riscv64
## and wasm by `ir::sig_pins_legacy`; see `test/package/ir1711_some_first_cross`). The enum is one
## pointer word with no discriminant whatever its variant order (Types §6.2): `Some` is discriminant 0
## here, and the variant is tested by its meaning — `None` is `word == 0`, `Some` is `word != 0`. A
## test against the discriminant would take `Some(p)` for `word == 0`: the null `t` would reach the
## `Some` arm's `deref(p)`, a null dereference (139), never a quiet 42.
## The absent case WRITES the null pattern: `t` answered `Some`, is re-assigned `None`, and must answer
## `None` after it. 42 when every check held; otherwise the failed check's own code, 101 upward.
## On the PARENT the builder refused `main` (`NotYet(stmt Assign …)`, the Some-first folded local), so
## the program went to each backend's legacy emitter: x86_64 answered 42, aarch64 and riscv64 trapped
## (133) and wasm trapped (134). On the head `main` is Built and selected from the IR on all four
## (one `ir: selected` marker in each dump), and every backend answers 42 (measured).
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
      output = "ir1711-local",
    ),
  ],
)
## expect: run 42
