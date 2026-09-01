## Issue #269 residual — a nested package module can name the private OsArena through its std::os
## ancestor. The source module is intentionally not an ambient stdlib file: its direct return must
## still be checked before a backend could treat Result(OsArena, IoError) as OsArena.
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
      output = "issue269-os-arena-return",
    ),
  ],
)
