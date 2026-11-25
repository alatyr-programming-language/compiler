## Issue #1929 — a struct literal with a path head (`geo::S(b = 2, a = 40)`) binds each named field to
## the field of that name (Types §9.3; Grammar `struct-ctor ::= type-expr "(" field-init … ")"`), written
## order notwithstanding. No module alias and no same-named decoy. Answers 40 + 2 = 42.
##
## NON-VACUOUS: at da8f96af (omen, native x86_64) every backend stored the values in written order:
## `v.a` read 2 and this answered 4.
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
      output = "issue1929-qualified-out-of-order",
    ),
  ],
)
## expect: run 42
