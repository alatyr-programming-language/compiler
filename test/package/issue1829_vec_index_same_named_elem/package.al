## Issue #1829 — `alloc::vec` indexing over an element type whose bare name several modules declare
## (Modules §3, Declarations §5: a bare type name is the declaration nearest up the chain from the
## module whose text spells it). The root, an unrelated sibling `m` and `geo` each declare a different
## `Node`. The root reads `v[1].b + v[0].b` over its own `Node` (8 + 20); `geo::child` reads
## `v.at(0).b` over `geo`'s, its nearest ancestor's (14). `m::zero()` adds 0. Answers 42.
##
## NON-VACUOUS: see the PR for the parent's answer on omen (native x86_64); the inferred element
## type was declined for a name two modules declare, and the field read off the untyped result
## answered the constant 0.
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
      output = "issue1829-vec-index-same-named-elem",
    ),
  ],
)
## expect: run 42
