## MOD-8 regression: a single-file root's `exit` trigger is already in the ambient path list.
## The driver must not append lib/base/process.al a second time; the root still emits and runs.
app := Package(
  version = "0.1.0",
  target_dir = "target",
  targets = [Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu,
    container = Container.elf, output = "mod8-root-process-single")],
)

_start := fn() {
  exit(42)
}
