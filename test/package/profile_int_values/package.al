app := Package(version = "0.1.0", source_dir = "src", target_dir = "target",
    profile_flags = [
        FlagDecl(name = "opt", type = u64, default = 7),
    ],
    profiles = [
        Profile(name = "release", flags = [
            FlagSet(name = "opt", value = 42),
        ]),
    ],
    targets = [
        Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu, container = Container.elf, entry = "_start", output = "profile-int-values"),
    ])
