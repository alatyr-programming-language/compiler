## Issue #1915 review / #1920: `geo::child` binds `f := other::h`, renaming a GENERIC function, and that
## binding shadows `geo`'s own generic `f` (Declarations §6.1; Modules §4.1). The lowering cannot yet
## instantiate `other::h` under the name `f`; before this refusal `check` accepted the call and the
## build stopped at the linker on an undefined `other__h`, with no source location. Both `check` and
## `build` must now refuse the call itself, at line 2 of `geo::child`, citing #1920.
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
      output = "issue1915-renamed-generic-alias-reject",
    ),
  ],
)
## expect: reject "an alias that renames a generic function" "at line 2"
