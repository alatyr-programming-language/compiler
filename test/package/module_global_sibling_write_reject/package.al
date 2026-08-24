## Modules §3 — the WRITE half of the sibling-visibility reject, and the worst of the family: a bare
## `PRIV = …` to a sibling's global used to bind a FRESH FRAME LOCAL and store through it, smashing
## the stack (the probe exited 139, SIGSEGV). The write must FAIL LOUD; it may not reach the emitter
## as a frame place. Its array-element twin is `module_global_sibling_arr_reject` (a different
## emitter path — SIB element addressing off the base's slot).
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
      output = "module-global-sibling-write-reject",
    ),
  ],
)
