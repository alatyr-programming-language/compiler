## Modules §8 — a package that USES its path dependency through the dependency's ALIAS NAMESPACE:
## `d::math::answer()`, where `d` is this manifest's `alias` for the package at `../dep_lib`. The
## dependency's items live under `<alias>::<module>::…` (its module is named `d__math`, so the call
## mangles to `d__math__answer`); an alias is package-LOCAL naming, never the dependency's identity
## (MOD-10 — the graph keys a path dependency by its lexically-normalized absolute path). Exits
## 7 + 35 = 42.
app := Package(
  version = "0.1.0",
  source_dir = "src",
  target_dir = "target",
  dependencies = [
    Dependency(name = "dep_lib", alias = "d", source = DepSource.Path("../dep_lib")),
  ],
  targets = [
    Target(
      arch = Arch.x86_64,
      os = Os.linux,
      env = Env.gnu,
      container = Container.elf,
      entry = "_start",
      output = "dep-alias-use",
    ),
  ],
)
