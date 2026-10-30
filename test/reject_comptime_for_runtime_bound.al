## e2e (#696) — a `comptime for` range bound that is a run-time value has no comptime value, so
## Comptime §9.1 makes it a compile error. On the parent (`2cf60b45`) every backend built this clean,
## read the bound as 0, unrolled nothing and exited 1. Here x86_64 refuses it with a located
## diagnostic, and aarch64, riscv64 and wasm emit a trap in place of the loop.
four := fn() -> u64 { 4 }

main := fn() -> u64 {
  mut n : u64 = 0
  comptime for i in 0 .. four() { n = n + 1 }
  if n != 4 { return 1 }
  return 42
}
