## Issue #972 / spec#192 — a scanned source file whose stem is not an identifier makes the package
## ill-formed (Modules §1). `src/a-b.al` maps to the module path segment `a-b`, which no path can spell,
## so the build is refused with a Config diagnostic located by that file's path, before any source is
## read. There is no `-` to `_` mapping.
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
      output = "issue972-stem-file-reject",
    ),
  ],
)
## expect: reject "src/a-b.al" "this file maps to the module path segment `a-b`, which is not an identifier"
