app := Package(
  source_dir = "src",
  target_dir = "target",
  profile_flags = [FlagDecl(name = "flag", type = bool, default = "not bool")],
  targets = [Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu, container = Container.elf, entry = "_start", output = "bad")],
)
