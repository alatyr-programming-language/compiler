## Issue #1744, review of PR #1748 (B1): a module-path call `b::f()` from a root that declares its own `f`.
## The twins emit every function under its bare name, so `b::f` and the root's `f` would share a label;
## the driver then keeps the entry module's declarations alone and rewrites no qualified callee (#41).
## The IR builder must not answer `b::f` with the root's `f` there: it builds the call only when the
## resolved declaration belongs to the module the head names, so the twins keep their legacy trap.
## NON-VACUOUS: on the PR's first head 0f90e2a9 aarch64, riscv64 and wasm answered 20 (`f() + f()`, the
## root's `f` twice) where their base trapped (133/133/134). x86_64 sees every module and answers 42.
## Expected exit 42: 32 from `b::f` and 10 from the root's `f`.
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
      output = "issue1744-qualified-collision-ir",
    ),
  ],
)
## expect: run 42
