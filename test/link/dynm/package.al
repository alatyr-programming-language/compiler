## MOD-9 e2e (DYNAMIC link): a package that links libm dynamically. `libs = [Lib(name = "m",
## link = LinkMode.dynamic)]` makes the whole binary dynamic, so the toolchain links it via
## `cc -nostartfiles <obj> -o <out> -lm` (keeps this program's own `_start`, supplies the ELF
## interpreter + default search paths). `main` calls libm `sqrt`; sqrt(1764.0) = 42.0 -> exit 42.
app := Package(
    version = "0.1.0",
    source_dir = "src",
    target_dir = "target",
    libs = [
        Lib(name = "m", link = LinkMode.dynamic),
    ],
    targets = [
        Target(
            arch = Arch.x86_64,
            os = Os.linux,
            env = Env.gnu,
            container = Container.elf,
            entry = "_start",
            output = "dynm"
        ),
    ]
)
