app := Package(
  source_dir = "src",
  target_dir = "target",
  profiles = [Profile(name = "debug", flags = [FlagSet(name = "missing", value = true)])],
  targets = [Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu, container = Container.elf, entry = "_start", output = "bad")],
)
