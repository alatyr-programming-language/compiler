## #1725 review (#1723) — the control: the same callee called qualified (`m::get(p)`).
app := Package(
  version = "0.1.0",
  source_dir = "src",
  target_dir = "target",
  targets = [
    Target(
      arch = Arch.x86_64,
      os = Os.linux,
      env = Env.gnu,
      container = Container.elf,
      kind = Kind.executable,
      output = "ir1723-qualified-deref-struct",
    ),
  ],
)
## Due 42 everywhere. aarch64, riscv64 and wasm trap at `ptr(mut t)` (#1188).
## expect: run 42
