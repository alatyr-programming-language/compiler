## Issue #972 / spec#192 — a scanned directory whose stem is not an identifier makes the package
## ill-formed (Modules §1). `src/my-lib/` maps to the module path segment `my-lib`, so the diagnostic is
## located by the DIRECTORY's path, not by the file inside it.
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
      output = "issue972-stem-dir-reject",
    ),
  ],
)
## expect: reject "src/my-lib" "this directory maps to the module path segment `my-lib`, which is not an identifier"
