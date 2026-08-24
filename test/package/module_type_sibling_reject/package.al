## Modules §3 — SIBLING REJECTION for a bare TYPE name. `geo::child` names `Box` bare, and the ONLY
## declarations of `Box` are in two unrelated top-level modules: siblings of `geo`, non-`pub`, on
## nobody's ancestor chain. §3 lets `geo::child` name NEITHER, and nothing in the module says which
## one it means, so the reference is unanswerable and must be a LOCATED reject.
##
## The single-sibling case is deliberately NOT this fixture: one declaration program-wide keeps
## resolving (the unique-declaration leniency the whole tree leans on for every ambient prelude type).
## It takes TWO for the resolver to have been guessing — and guessing is what it did: measured on the
## frozen seed before TYPE-ANCESTOR this program BUILT and returned 50, having silently sized
## `atwo`s 16-byte `Box` because it sorts last in declaration order.
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
      output = "module-type-sibling-reject",
    ),
  ],
)
