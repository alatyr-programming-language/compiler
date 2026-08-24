## Modules §3 + §1 (MOD-12) + Types §4.1 — a BARE TYPE NAME resolved UP the module tree. `src/geo.al`
## and `src/geo/` are one module (MOD-12): the file supplies `geo`'s own items, the directory its
## children. §3 makes those items visible DOWN the tree, `pub` or not, so `geo::child` and
## `geo::deep::leaf` may name them by bare name. `src/aother.al` and `src/zother.al` declare the SAME
## names with WIDER shapes, are non-`pub`, are nobody's ancestor — §3 makes them unnameable from
## `geo` — and they bracket `geo.al` in declaration order, so the fixture pins BOTH tie-breaks at
## once: the bare TYPE resolver was LAST-wins (the `zother` side), the struct field-order table and
## the `@require` scan were FIRST-wins (the `aother` side).
##
## Every shape here is a SIZE or a VALIDITY, because those are the only observable differences a
## same-named type can produce: a struct's `size()`, a raw union's `size()`, an enum's `size()`, a
## type ALIAS's target, a generic type ARGUMENT's instance layout, a struct literal's field-name set,
## and which `@require` predicate runs. Measured on the frozen seed before TYPE-ANCESTOR:
## `geo::child::run()` returned 74 and `geo::deep::leaf::run()` 33 (both sized `zother`'s types).
##
## child 25 + grandchild 17 = 42.
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
      output = "module-type-ancestor",
    ),
  ],
)
