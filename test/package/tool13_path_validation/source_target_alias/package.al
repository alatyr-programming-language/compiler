app := Package(version = "0.1.0",
  source_dir = "target",
  target_dir = "target/../target",
  targets = [Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu,
    container = Container.elf, entry = "_start", output = "bad")])
