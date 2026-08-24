## Issue #51 / Modules §8 — a path dependency may contain its own `lib/` directory.
## Its module path includes that directory, so a consumer's alias must remain the first
## symbol component when the module is named. This package is consumed by
## `dep_lib_nested_use`; it has no entry of its own.
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
      output = "dep-lib-nested",
    ),
  ],
)
