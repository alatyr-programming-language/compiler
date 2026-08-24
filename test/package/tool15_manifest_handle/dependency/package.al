## TOOL-15 dependency visibility: `app` belongs only to this package's root.
app := Package(
  version = "0.1.0",
  source_dir = "src",
  target_dir = "target",
  dependencies = [
    Dependency(name = "d", source = DepSource.Path("../dependency_dep")),
  ],
  targets = [
    Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu, container = Container.elf, entry = "_start", output = "tool15-dependency"),
  ],
)
