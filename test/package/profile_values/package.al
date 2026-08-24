app := Package(
  source_dir = "src",
  target_dir = "target",
  default_profile = "debug",
  profile_flags = [
    FlagDecl(name = "word", type = str, default = "alpha beta"),
    FlagDecl(name = "mode", type = Mode, default = Mode.slow),
  ],
  profiles = [
    Profile(name = "fast", flags = [
      FlagSet(name = "word", value = "release ca"),
      FlagSet(name = "mode", value = Mode.fast),
    ]),
    Profile(name = "release", flags = [
      FlagSet(name = "word", value = "release ca"),
      FlagSet(name = "mode", value = Mode.fast),
    ]),
  ],
  targets = [Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu, container = Container.elf, entry = "_start", output = "profile-values")],
)
