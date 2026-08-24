app := Package(
  version = "0.1.0",
  target_dir = "src/out",
  targets = [Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu,
    container = Container.elf, entry = "_start")],
)
