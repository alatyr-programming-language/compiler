app := Package(version = "0.1.0", target_dir = "target",
  targets = [Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu,
    container = Container.elf, output = "mod8-root-controls")])

pick := fn(x : u64) -> u64 { return x }
pick := fn(x : str) -> str { return x }
answer := fn() -> u64 when target.arch == Arch.x86_64 { return 41 }
answer := fn() -> u64 when target.arch == Arch.aarch64 { return absent_on_aarch64() }
main := fn() -> u64 { return pick(1) + answer() }
