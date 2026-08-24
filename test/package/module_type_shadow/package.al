## Modules §3 — a NEARER declaration SHADOWS a farther one on the ancestor chain, for TYPES. The
## chain is ordered by module-path LENGTH, so `geo::child`s own `Box` outranks `geo`s `Box`, which in
## turn outranks nothing at all in an unrelated module. Two decoys bracket `geo.al` in declaration
## order so neither the old LAST-wins nor the old FIRST-wins tie-break can pass by accident.
##
## Struct and enum have SEPARATE resolvers (`struct_decl_of` / `enum_decl_of`), so each gets its own
## shadowing child: `geo::child` shadows the struct, `geo::edge` shadows the enum. Measured on the
## frozen seed before P1-TYPE-ANCESTOR: `child::run()` returned 46 (`zother`s 32-byte `Box`) and
## `edge::run()` 44 (`zother`s 32-byte `E`) — 90 instead of 42.
##
## child 22 + edge 20 = 42.
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
      output = "module-type-shadow",
    ),
  ],
)
