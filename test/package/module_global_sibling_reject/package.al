## Modules §3 — privacy flows DOWN the tree: a module sees its OWN and its ANCESTORS' declarations,
## never a SIBLING's. `PRIV` is not `pub` and `other` is `geo`'s sibling, so the bare name `PRIV` in
## `other` resolves to no declaration `other` may address. It used to become a fresh FRAME LOCAL and
## the read returned an uninitialised slot (silently 0) — the forbidden silent outcome. FAIL LOUD.
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
      output = "module-global-sibling-reject",
    ),
  ],
)
