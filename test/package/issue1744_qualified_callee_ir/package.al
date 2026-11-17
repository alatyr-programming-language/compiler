## Issue #1744: a call spelled with a module path (`m::add(…)`) is built through the shared IR. The IR
## builder takes the callee from the resolver x86's own call emission uses. A callee whose signature
## names a type that both modules declare (`S`) stays refused, so it keeps its legacy call. Expected
## exit 42: 22 from `m::add`, 11 from the two fields of `m::mkq`'s result, and 9 from `m::get` of
## `m::mks`'s result.
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
      output = "issue1744-qualified-callee-ir",
    ),
  ],
)
## expect: run 42
