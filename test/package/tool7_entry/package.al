## TOOL-7 — a PACKAGE whose program declares the manifest's `Target.entry` symbol itself. `build`/`run`
## link the executable with this `_start` and drop the `@test` item (TOOL-5); `alatyr test` builds a
## SEPARATE artifact with the runner's entry and does not link this one (before TOOL-7 the assembler
## rejected the test artifact: "symbol `_start' is already defined", rc 13).
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
      entry = "_start",
      output = "tool7-entry",
    ),
  ],
)
