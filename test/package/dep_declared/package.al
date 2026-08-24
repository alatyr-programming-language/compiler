## Tooling §2.4 / Modules §8 — a package that DECLARES a path dependency and never references it.
## Declaring a dependency must not change what the ROOT package emits: before this fixture, adding the
## `dependencies` field alone made the build discover an EMPTY module list, fall back to compiling
## `package.al` (the manifest) as a single-file program, and fail at link with an undefined `main`.
## Nothing here references the dependency, so reachability pruning drops its code entirely — the point
## is only that the ROOT package's own `main__main` still reaches the artifact. Exits 42.
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
      output = "dep-declared",
    ),
  ],
)
