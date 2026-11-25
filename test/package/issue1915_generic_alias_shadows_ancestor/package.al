## Issue #1915: a descendant module's alias `f := other::f` of a GENERIC function shadows an
## ancestor's generic of that name within the descendant (Declarations §6.1; Modules §4.1). `geo`
## declares its own generic `f` (x + 100); `geo::child` aliases `other`'s (x + 2). Due exit 42:
## `geo::child::run()` 42 through the alias and `geo::pf()` 100 through `geo`'s own, so 42 + 100 - 100.
## A call bound to `geo`'s instance adds 98.
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
      output = "issue1915-generic-alias-shadows-ancestor",
    ),
  ],
)
## expect: run 42
