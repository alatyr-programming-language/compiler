- **`alatyr aarch64` compiles for the aarch64 machine model it emits (#1578).** The verb published no
  model, so `target.*` in sema and in `comptime if` answered x86_64 while the emitter wrote aarch64: a
  `when target.arch == Arch.aarch64` declaration was checked as absent but emitted, and a
  `comptime if` on `target.os` or `target.env` ran into a `brk #0` trap (exit 133). The verb now
  publishes `Machine.Linux(arch = Arch.aarch64)` with env gnu, and a `when`-alternative selected for
  aarch64 is checked like any other declaration, so a program whose aarch64 alternative names an
  undefined function now stops compiling. riscv64 follows; wasm waits on the spec.
