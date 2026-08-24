## Modules §3/§4 — every LEGAL cross-module naming shape in one package, so the §3 check cannot be
## tightened into rejecting a program the specification allows. `geo` exposes a `pub` surface upward;
## `geo::child` (a DESCENDANT) reads `geo`'s NON-`pub` internals, which §3 explicitly permits; `main`
## (a SIBLING of `geo`) may name only the `pub` surface, and does so through a path, a module alias,
## a listed member projection, a `pub` re-export, and a qualified UFCS call.
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
      entry = "_start",
      output = "visibility-legal",
    ),
  ],
)
