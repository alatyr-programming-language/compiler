## Issue #403, the FUNCTION-AS-VALUE spelling — the one with no other guard at all. A bare `Var`
## naming a private sibling function reaches neither the callee check (it is not a call) nor
## `sema_global_ref_bad`, which excludes `is_fn` declarations. On the parent `f := secret; f()` built
## and ran to 42 from a module Modules §3 lines 80-85 forbid from naming `secret`.
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
      output = "issue403-bare-private-fnvalue-reject",
    ),
  ],
)
