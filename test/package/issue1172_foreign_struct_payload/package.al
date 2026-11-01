## Issue #1172 / Types §6 (enum payloads) — an enum variant whose payload is a struct declared in ANOTHER module (`Arr(m::S)`) carries all four of its words through a `match` binding.
## Expected exit 42. NON-VACUOUS: on the parent 9b9fea98 (x86_64) it exits 4.
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
      output = "issue1172-foreign-struct-payload",
    ),
  ],
)
## expect: run 42
