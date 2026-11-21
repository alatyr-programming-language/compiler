## #1822 / Functions §2.3, §5.1; Modules §4.1.1: a statement call through a listed member projection
## `(mix) := m` that omits an `in` parameter of `m::mix` is held to the same rule as a local callee.
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
      output = "issue1822-alias-short-call-reject",
    ),
  ],
)
## expect: reject "leaves parameter `n` unbound" "at line 3"
