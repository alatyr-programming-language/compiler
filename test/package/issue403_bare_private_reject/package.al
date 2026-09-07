## Issue #403 — the reported reproducer, as an EXTERNAL package. Modules §3 lines 90-92 make the
## `pub` chain to the root the only way anything reaches outside a package, and this package is not
## `base::str` nor nested in it, so the private `char_byte` is unnameable here in BOTH spellings.
## On the parent this built rc=0 and the artifact exited 42; the qualified spelling of the same call
## was already refused. `test/package/issue403_bare_private_legal` is the positive counterpart.
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
      output = "issue403-bare-private-reject",
    ),
  ],
)
