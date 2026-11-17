## #1725 review (#1723) — a callee reached through an import alias returns `ptr(E)`, and the root declares a different `E`.
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
      output = "ir1723-alias-deref-enum",
    ),
  ],
)
## Due 42 (Modules §3, §4.1). x86_64 refuses the build at `rd`'s match (#1734: a callee reached
## through an alias has its signature types resolved in the caller's module, and the IR refuses
## the read rather than lay out the root's `E`). aarch64, riscv64 and wasm trap first at `main`'s
## call `m::mk()`, an undefined callee beside the alias (#1739).
## expect: run 42
