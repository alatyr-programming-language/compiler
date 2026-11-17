## #1725 review (#1723) — the narrowness control: callees reached through import aliases, with no root type of the same name.
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
      output = "ir1723-alias-deref-same",
    ),
  ],
)
## Due 42 everywhere. aarch64, riscv64 and wasm trap first at `main`'s call to `m`, an undefined
## callee beside the alias (#1739).
## expect: run 42
