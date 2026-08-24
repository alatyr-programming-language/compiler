## TOOL-15 Config diagnostic: the manifest handle is not publishable.
pub app := Package(
  version = "0.1.0",
  source_dir = "src",
  target_dir = "target",
  targets = [
    Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu, container = Container.elf, entry = "_start", output = "tool15-pub"),
  ],
)
