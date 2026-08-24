## Modules §3 — a SIBLING of the calling module's ancestor declares the bare name, and nothing on the
## calling chain does. Neither declaration is nameable from `geo::child` (privacy flows DOWN, exposure
## UP only through `pub`, and there is no friend / sibling / package-private access beyond that), so
## the call has NO answer and must be a located reject. Before this it took the first declaration in
## declaration order and silently called an unrelated module's private function.
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
      output = "module-fn-sibling-reject",
    ),
  ],
)
