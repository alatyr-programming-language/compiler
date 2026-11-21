## Issue #1808 — a generic instance's symbol names the module that declares each type argument. Two
## modules declare a struct `Node` with different field orders, and the generic functions of `m` are
## instantiated at `m::Node` (from the root and from `m` itself) and at the root's own `Node`. These are
## different instances (Comptime §3.2), so each gets its own symbol and reads its own layout; before the
## fix all of them were the one label `m__…__Node`, defined once, and the root's `Node` was read with
## `m`'s layout (x86_64 answered 2 where the program says 40).
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
      output = "issue1808-instance-declaring-module",
    ),
  ],
)
## spec: Comptime §3.2, §3.4; Modules §6.7
## expect: run 42
