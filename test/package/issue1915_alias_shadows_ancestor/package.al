## Issue #1915: a name a descendant module binds itself with an alias `f := other::f` shadows an
## ancestor's binding of that name within the descendant and within its own descendants
## (Declarations §6.1; Modules §4.1). `geo` declares its own `f` (x + 100); `geo::child` aliases
## `other`'s (x + 2), and `geo::child::leaf` inherits the alias from `child`. Due exit 42:
## `geo::child::run()` 42 through the alias, `geo::child::leaf::run()` 42 through the inherited alias,
## and `geo::pf()` 100 through `geo`'s own `f`, so 42 + 42 + 100 - 142. A call bound to `geo`'s `f`
## in either descendant adds 98.
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
      output = "issue1915-alias-shadows-ancestor",
    ),
  ],
)
## expect: run 42
