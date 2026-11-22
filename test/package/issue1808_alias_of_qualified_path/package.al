## Issue #1808 — an alias whose right-hand side is a path into a nested module is the type at that path
## (Declarations §1.3). `A := k::C` in `m` and `A := m::k::C` in the root both name `m::k`'s `pub C := u64`
## (Modules §1, §2), so `rd` at either `A` is `rd` at `u64`. Each call reads all eight bytes of 10759:
## 42 + 42 - 42 = 42. Before, the path stayed unresolved, its text reached the instance label as
## `m__rd__k::C`, and the assembler refused the program.
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
      output = "issue1808-alias-of-qualified-path",
    ),
  ],
)
## spec: Modules §1, §2, §3; Declarations §1.3; Comptime §3.2
## expect: run 42
