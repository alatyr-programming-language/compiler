app := Package(
  version = "0.1.0",
  source_dir = "src",
  target_dir = "target",
  targets = [Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu,
    container = Container.elf, output = "mod8-root-decl-duplicate")],
)

dup := fn() -> u64 { return 7 }
dup := fn() -> u64 { return 9 }
main := fn() -> u64 { return 42 }
