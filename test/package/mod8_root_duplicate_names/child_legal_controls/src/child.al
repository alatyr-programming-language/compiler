pick := fn(x : u64) -> u64 { return x }
pick := fn(x : str) -> str { return x }
answer := fn() -> u64 when target.arch == Arch.x86_64 { return 41 }
answer := fn() -> u64 when target.arch == Arch.aarch64 { return absent_on_aarch64() }
pub run := fn() -> u64 { return pick(1) + answer() }
