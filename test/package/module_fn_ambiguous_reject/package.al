## Modules §3 — the AMBIGUITY must not fail silently EITHER WAY. Two unrelated top-level modules
## declare `helper`; the calling module declares none and is nested in neither, so no ranking can
## choose and no §4.1.1 binding says which is meant. Picking the first (or the last) declaration in
## declaration order would call a function the program may not name, which is a wrong VALUE, so the
## bare call is a located reject naming the calling module. Qualifying it is the fix a user applies.
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
      output = "module-fn-ambiguous-reject",
    ),
  ],
)
