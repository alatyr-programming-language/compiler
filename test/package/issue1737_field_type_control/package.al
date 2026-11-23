## Issue #1737, the control — the same program with no `Inner` in the root module, so only
## `wide`'s declaration can lay out `P`. Answers 42 + 0 = 42 before and after the fix.
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
      output = "issue1737-field-type-control",
    ),
  ],
)
## expect: run 42
