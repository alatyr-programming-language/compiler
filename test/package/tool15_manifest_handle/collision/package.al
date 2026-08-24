## TOOL-15 Semantic duplicate: the root child `mylib.al` shares the manifest binding name.
mylib := Package(
  version = "0.1.0",
  source_dir = "src",
  target_dir = "target",
  targets = [
    Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu, container = Container.elf, entry = "_start", output = "tool15-collision"),
  ],
)
