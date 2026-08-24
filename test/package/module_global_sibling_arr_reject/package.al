## Modules §3 — the ARRAY-ELEMENT write to a sibling's global. It takes a different emitter path from
## the scalar write (`Stmt::IndexAssign` resolves the base through the slot table, not the global
## label), and it used to compute the element address off an UNBOUND frame slot — `leaq -8(%rbp), %rbx`
## — and store through it: a stack smash with no diagnostic. It must FAIL LOUD.
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
      output = "module-global-sibling-arr-reject",
    ),
  ],
)
