## Modules §3 + §1 (MOD-12) + Memory §2.2 — a module-level global reached from a DESCENDANT module.
## `src/geo.al` and `src/geo/` are one module (MOD-12): the file supplies `geo`'s own items, the
## directory its children. §3 makes those items visible DOWN the tree, `pub` or not, so `geo::child`
## and `geo::deep::leaf` may name them — by bare name (they are ancestors' items) and by the qualified
## path alike. Every reference must be addressed through the MOD-6 mangled `.data` symbol
## `geo__<NAME>(%rip)`; each used to compile to an uninitialised FRAME SLOT instead, so the read
## returned 0, the write smashed the stack and the array-element write faulted.
##
## Covers, from the child by BARE name: a scalar read, a scalar write, a compound assignment, an
## ARRAY-ELEMENT write, a `str` (§7 view) read, a folded const scalar and a const ARRAY element; and
## from the grandchild by QUALIFIED path: a write, a compound assignment, an array-element write and
## the reads. 25 + 17 = 42.
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
      output = "module-global-ancestor",
    ),
  ],
)
