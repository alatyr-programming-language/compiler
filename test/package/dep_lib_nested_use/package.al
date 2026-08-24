## Issue #51 / Modules §8 — the dependency at `../dep_lib_nested` contains
## `src/lib/thing.al`. The consumer must reach it through the local alias and
## preserve the whole module path. The artifact exits 42.
app := Package(
  version = "0.1.0",
  source_dir = "src",
  target_dir = "target",
  dependencies = [
    Dependency(name = "dep_lib_nested", alias = "d", source = DepSource.Path("../dep_lib_nested")),
  ],
  targets = [
    Target(
      arch = Arch.x86_64,
      os = Os.linux,
      env = Env.gnu,
      container = Container.elf,
      entry = "_start",
      output = "dep-lib-nested-use",
    ),
  ],
)
