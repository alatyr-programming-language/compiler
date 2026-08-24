## Omitted source_dir uses the spec default `src`; this is a multi-file package, not a single-file
## package.al program.
app := Package(version = "0.1.0",
  targets = [Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu,
    container = Container.elf, entry = "_start")])
