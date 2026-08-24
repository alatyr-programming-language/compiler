app := Package(
  version = "0.1.0",
  source_dir = "src",
  target_dir = "target",
  limits = [Limit.no_alloc, Limit.freestanding],
  targets = [Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu, container = Container.elf, kind = Kind.executable, output = "limits-capabilities")],
)
