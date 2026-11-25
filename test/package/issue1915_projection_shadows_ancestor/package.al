## Issue #1915: a name a listed projection `(f, g) := other` binds in a descendant module shadows an
## ancestor's binding of that name within the descendant (Declarations §6.1; Modules §4.1.1). `geo`
## declares its own `f` (x + 100) and a two-parameter `g` (x + y + 100); `geo::child` projects
## `other`'s one-parameter `f` (x + 2) and `g` (x + 1). The checker must judge `g(41)` against
## `other::g`, and the lowering must call `other`'s functions. Due exit 42: `geo::child::run()`
## 42 + 42 through the projection and `geo::pf()` 100 + 100 through `geo`'s own, so 84 + 200 - 242.
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
      output = "issue1915-projection-shadows-ancestor",
    ),
  ],
)
## expect: run 42
