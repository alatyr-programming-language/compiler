## Modules §3 — when a module and one of its ANCESTORS both declare a global of the same name, the
## NEAREST declaration wins: a bare `G` in `geo::child` is `geo::child`'s own, and the ancestor's is
## reached only through the qualified path `geo::G`. Without the nearest-wins rule the resolver took
## the LAST matching declaration in decl order, so which global a bare name meant depended on the
## order the driver happened to read the module files in. 41 + 1 = 42.
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
      output = "module-global-shadow",
    ),
  ],
)
