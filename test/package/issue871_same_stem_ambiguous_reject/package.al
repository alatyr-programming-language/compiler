## Modules §1/§5 (#871) — the ROOT names `x`, but neither `x` is in its scope: `src/a/x.al` and
## `src/b/x.al` are `a::x` and `b::x`, and only their last segment matches. Binding either is a
## guess (it bound the last one), so the build refuses the projection at its call.
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
      output = "issue871-same-stem-ambiguous-reject",
    ),
  ],
)
