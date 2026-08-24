## Modules §8 / Tooling §2.4 — the DEPENDENCY package consumed by `dep_declared` and `dep_alias_use`
## through `DepSource.Path("../dep_lib")`. It is never built on its own by the gate: a dependency is
## compiled as part of the CONSUMING package's build, and its items live under the consumer's alias
## (`d::math::answer`), never flatly in the consumer's namespace. It declares no `main` — a dependency
## is a library, and the entry stays in the root package.
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
      entry = "_start",
      output = "dep-lib",
    ),
  ],
)
