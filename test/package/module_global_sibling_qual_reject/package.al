## Modules §3/§4 — the QUALIFIED spelling does not widen visibility: `geo::PRIV` names a non-`pub`
## declaration of a SIBLING module, which §3 keeps invisible outside `geo` and its descendants. The
## qualified form used to compile to a frame-slot read (and, for a write, to nothing at all — a silent
## no-op), so it must FAIL LOUD instead. `pub` + a qualified path is the spelling that works.
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
      output = "module-global-sibling-qual-reject",
    ),
  ],
)
