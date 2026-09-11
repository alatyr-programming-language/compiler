## Issue #655's positive half: the same nested-submodule shape with every name bound. Enabling the
## checker on nested submodules must not start refusing legal ones — a descendant reading its
## ancestor's non-`pub` declaration by bare name (Modules §3) is the shape `src/lower/*.al` itself
## uses, and it is the one this fixture holds the checker to.
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
      output = "issue655-nested-legal",
    ),
  ],
)
