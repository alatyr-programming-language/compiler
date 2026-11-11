- **`alatyr riscv64` compiles for the riscv64 machine model it emits (#1578).** The same defect and
  fix as for `alatyr aarch64`: the verb publishes `Machine.Linux(arch = Arch.riscv64)` (env gnu, the
  only env of that row), and its `comptime if` folds every `target.*` facet from that model instead of
  trapping on `target.os` and `target.env`. Over a package the verb replaces the manifest's arch, so a
  manifest whose env riscv64 does not support (`Env.musl`) is now a located Config error instead of a
  riscv64/musl build no supported target describes.
