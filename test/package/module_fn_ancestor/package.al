## Modules §3 + §1 (MOD-12) — a BARE CALL resolved UP the module tree. `src/geo.al` and `src/geo/`
## are one module (MOD-12): the file supplies `geo`'s own items, the directory its children. §3 makes
## those items visible DOWN the tree, `pub` or not, so `geo::child` and `geo::deep::leaf` may name
## them by bare name. `src/aother.al` declares the SAME names, is non-`pub`, is nobody's ancestor —
## §3 makes it unnameable from `geo` — and it sorts FIRST in declaration order, which is exactly what
## the resolver used to pick: `geo__child__run` emitted `call aother__helper` and the program returned
## 22 instead of 42. Covers a plain fn one step up, a plain fn TWO steps up (the grandchild), and a
## GENERIC fn one step up (whose monomorphized instance must be collected from the same module the
## call is emitted against, or the instance is never emitted and the link fails).
## 20 + 5 = 25 from the child, 20 - 3 = 17 from the grandchild; 25 + 17 = 42.
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
      output = "module-fn-ancestor",
    ),
  ],
)
