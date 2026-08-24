## Modules §3 — SHADOWING on the ancestor chain: a name declared in BOTH the calling module and an
## ancestor resolves to the NEAREST declaration, and a name declared only in the ancestor still
## resolves one step up. The decoy `src/aother.al` declares both names too and sorts first.
## 30 (the child's own `helper`) + 12 (`geo`'s `bump`, one step up) = 42.
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
      output = "module-fn-shadow",
    ),
  ],
)
