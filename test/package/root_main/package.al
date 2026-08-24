## Manifest §6 / §140 + Modules §6.1 — the single-file package whose root declaration is `main`
## (no `_start`): the driver synthesizes the default ELF `_start` wrapper and calls the entry fn. The
## root module is ANONYMOUS, so `main` emits the UNPREFIXED symbol `main` and the wrapper must call
## `main` — not `package__main`. Built with AND without an explicit `package.al` argument; exits 42.
app := Package(
  version = "0.1.0",
  target_dir = "target",
  targets = [
    Target(
      arch = Arch.x86_64,
      os = Os.linux,
      env = Env.gnu,
      container = Container.elf,
      entry = "_start",
      output = "root-main",
    ),
  ],
)

ANSWER := 42

main := fn() -> u64 {
  return ANSWER
}
