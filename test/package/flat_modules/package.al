## Manifest §6 / §140 — the default package layout (no `source_dir`, so it defaults to "src"): the
## modules live below the package root's `src/` directory. `package.al` here is ONLY the manifest — it
## is excluded from the module list, so nothing in it is compiled and no declaration of its own is
## emitted. Built BOTH as
## `alatyr build package.al` from inside this directory (the BARE manifest path, which is also what a
## no-argument `alatyr build` normalizes to) and as `alatyr build <dir>/package.al` from outside; the
## two must discover the SAME module list (`main.al` + `util.al`). Exits 42.
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
      output = "flat-modules",
    ),
  ],
)
