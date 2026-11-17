## Issue #1753 / Functions §1.4 (FN-7), Modules §2 (MOD-3), §3, §5; Declarations §7.1 — the shape of
## `issue1753_method_recv_reject` in the OPPOSITE declaration order on both axes: the module is `z`,
## which sorts after `main`, and the root's `get(u64)` is written after `main`. Module-level
## declarations are order-independent, so the verdict is the same: no `get` the root can name accepts
## the `W` receiver. PARENT (#1755 head e43bebee), native x86_64: check 0, then x86_64 IR and legacy
## 113 on every run, aarch64 and riscv64 trap 133, wasm traps 134 (on main ce0f92e7, whose argument
## check stopped at the caller's position in module order, this order was already refused).
## Expected: check and build rc 1, located at the call, line 4 of `main`.
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
      output = "issue1753-method-recv-reject-late",
    ),
  ],
)
## expect: reject "type mismatch" "at line 4"
