## Issue #1737 — a struct's field types are those of its declaring module (Modules §3; Types §4.1).
## Module `wide` declares a one-word `Inner` and `P := struct { e : Inner, v : u64 }`; the root declares
## its own, three-word `Inner` and reads the qualified `wide::mk().v`. `v` sits at offset 8 of `wide`'s
## `P`, whatever the caller's `Inner` is. Answers 42 + 0 = 42.
##
## NON-VACUOUS: at `b74089f3` (omen, native x86_64) both x86_64 paths answered 0: the legacy layout
## resolved `Inner` in the caller's module and read `v` at the wrong offset. At `dc9e18e2` it answers 42.
## The control without the collision is `test/package/issue1737_field_type_control`.
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
      output = "issue1737-field-type-callee-module",
    ),
  ],
)
## expect: run 42
