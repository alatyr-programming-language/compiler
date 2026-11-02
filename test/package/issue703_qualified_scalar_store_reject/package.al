## Issue #703 residual / Modules §2, MOD-3 — module `a` STORES to `z::n.x`, a field of the sibling
## `z`'s pub mut SCALAR global `n`. Measured on the parent (main e77d025e, native x86_64): check 0,
## the store landed nowhere and `z::n` read back 5 (the program exited 39). Expected: check and
## build rc 1, located at line 2 in a.
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
      output = "issue703-qualified-scalar-store-reject",
    ),
  ],
)
## expect: reject "a scalar has no field to name"
