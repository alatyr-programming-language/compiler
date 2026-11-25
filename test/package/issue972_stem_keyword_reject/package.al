## Issue #972 / spec#192 — a stem spelled like a keyword is not an identifier (Grammar §2.3), so a
## scanned `src/fn.al` makes the package ill-formed (Modules §1).
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
      output = "issue972-stem-keyword-reject",
    ),
  ],
)
## expect: reject "src/fn.al" "segment `fn`, which is a keyword"
