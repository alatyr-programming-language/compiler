## Issue #1172 / Types §6 (enum payloads) — a payload that is a GENERIC struct instance from ANOTHER module (`Arr(m::G(u64))`) carries all four words.
## Expected exit 42. NON-VACUOUS: on the parent 9b9fea98 (x86_64) it exits 4 (the payload is sized as one word).
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
      output = "issue1172-foreign-generic-payload",
    ),
  ],
)
