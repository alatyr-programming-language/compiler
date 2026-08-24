## The Alatyr self-hosted compiler — package manifest (the spec's single `Package` value, TOOL-3).
## Sources live by path under `source_dir` (`src/`); build artifacts go to `target_dir` (`target/`).
## The bootstrap seed (`seed/alatyr`, a frozen STATIC self-host binary) builds this package into
## `target/debug/alatyr` — `debug` is the default build profile, `--release` selects `release` — and
## that compiler then reproduces itself byte-for-byte (TOOL-1; scripts/fixpoint.sh).
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
            output = "alatyr"
        ),
    ]
)

_start := fn() {
  r := main::main()
  exit(r)
}
