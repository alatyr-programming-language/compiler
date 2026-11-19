## Issue #1772: a bare call `f(…)` whose name several modules declare is built through the shared IR
## when the calling module's own scope binds it: its own declaration (`twice` in `main` and in `b`), an
## alias import (`step := a::step`) or a listed projection (`(half, dec) := b`) (Modules §4.1, §4.1.1,
## §5). Every name is also declared by another module with a different answer, so a call bound to the
## wrong module changes the total. A bare call into the calling module's own overload set (`pick`)
## stays refused and keeps the legacy emitter. Expected exit 42: `twice(2)` 8, `step(9)` 10,
## `half(8)` 4, `dec(5)` 4, `b::useb(4)` 13 through `b`'s own `twice`, and `pick(u8(3))` 3.
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
      output = "issue1772-bare-callee-ir",
    ),
  ],
)
## expect: run 42
