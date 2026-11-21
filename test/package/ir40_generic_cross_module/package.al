## IR-40 (#1786): IR-built calls to generic instances across modules. Both modules declare a generic
## `at`, as the compiler's own `decl_at` is declared in several modules, and `m`'s copy reads the NEXT
## word of the handle, so the two instances answer different values. A bare `at(u64, h)` means the
## calling module's own `at` (Modules §5); `m::pick(u64, …)` names `m`'s generic `pick`, whose instance
## label carries `m`'s path. Each call is built from the shared IR in a function of the root (`own`,
## `theirs`, `chosen`) and in `m` (`mown`), and `lboth` makes the same three calls from the legacy
## emitter (a float local keeps it there), so each instance has both kinds of caller.
## Expected exit 42: 10 (root `at` of word 0) + 20 (`m`'s `at`, word 1) + 12 (`pick` of the second value).
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
      output = "ir40-generic-cross-module",
    ),
  ],
)
## expect: run 42
