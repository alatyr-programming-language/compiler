## Issue #403, the TYPE spelling. `hid::Secret` is a private declaration of a SIBLING module, so
## Modules §3 lines 80-85 (privacy flows DOWN a module chain, never sideways) put it outside `main`.
## The bare struct-literal head resolved on the parent and the program ran to 42, because
## `sema_type_ambiguous` only rejected an AMBIGUOUS bare name (`hits > 1`) and never a private one.
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
      output = "issue403-bare-private-type-reject",
    ),
  ],
)
