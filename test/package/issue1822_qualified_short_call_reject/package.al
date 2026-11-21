## #1822 / Functions §2.3, §5.1: a qualified call `m::mix(42)` to another module's function that
## omits an `in` parameter. The callee sorts after the caller's module.
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
      output = "issue1822-qualified-short-call-reject",
    ),
  ],
)
## expect: reject "leaves parameter `n` unbound" "at line 2"
