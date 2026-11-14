## Issue #987 / Modules §6.6 — a package's own module file `src/alloc__vec.al` mangles to the same
## text as the standard library's `alloc::vec`, but it is not that module: module identity comes from
## the module tree, and a `__` inside a declared name is only a lint. #987's lowerer completes an
## implicit auto-ref call into its explicit form only for a callee of the standard library's
## `alloc::vec`, so it must not complete this package's `be.bget()` over a user generic `Box(E)`:
## that explicit form answers a wrong value on x86_64 (#1654), where the implicit call traps.
## Until #1654 makes the explicit form right, x86_64 keeps the trap (listed `run/139 #1654`); then the
## row goes and the package answers 42.
##
## PR #1650's head `4eb7d8bb`, which asked the module's mangled text (x86_64, omen): exit 100
## (`be.bget()` read the payload as 1, not 7). Its base `1a994f81`: SIGSEGV, as here.
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
      output = "issue987-user-module-alloc-vec",
    ),
  ],
)
## expect: run 42
