## #1725 review (#1723) — a callee reached through an import alias returns `ptr(E)`, and the root declares a different `E`.
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
      output = "ir1723-alias-deref-enum",
    ),
  ],
)
