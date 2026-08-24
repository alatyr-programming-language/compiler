## Manifest §6 / §140 + Modules §6.1 — a SINGLE-FILE package: `package.al` is BOTH the manifest and
## the whole program. Every declaration below `Package(…)` is ROOT-LEVEL, and a root-level
## declaration is UNPREFIXED (`_start` → `_start`, `bump` → `bump`, `COUNT` → `COUNT`) — the
## package-root module is ANONYMOUS, so there is no module name to prefix with. The const, the
## mutable global (a DATA symbol) and the helper fn (a TEXT symbol) are here on purpose: unprefixing
## is a property of the ROOT MODULE, not of the entry point.
##
## Exercised BOTH ways (the two must agree): `alatyr build/run/check package.al`, and — from inside
## this directory — a bare `alatyr build/run/check`, where the missing path argument is normalized to
## this `package.al` (Manifest §140: a trivial program needs no `Package` at all, so the path is
## optional). `_start` exits with 7 + 35 = 42.
app := Package(
  version = "0.1.0",
  target_dir = "target",
  targets = [
    Target(
      arch = Arch.x86_64,
      os = Os.linux,
      env = Env.gnu,
      container = Container.elf,
      entry = "_start",
      output = "root-single",
    ),
  ],
)

print := std::fmt::print

BASE := 35

mut COUNT := 0

bump := fn(x : u64) -> u64 {
  COUNT = COUNT + 1
  return x + BASE
}

_start := fn() {
  print("root-single\n")
  b := bump(7)
  exit(b + COUNT - 1)
}
