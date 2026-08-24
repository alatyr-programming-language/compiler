app := Package(
  version = "0.1.0",
  source_dir = "src",
  target_dir = "target",
  profile_flags = [
    FlagDecl(name = "release_path", type = bool, default = false),
  ],
  profiles = [
    Profile(
      name = "release",
      flags = [FlagSet(name = "release_path", value = true)],
    ),
  ],
  targets = [
    Target(
      arch = Arch.x86_64,
      os = Os.linux,
      env = Env.gnu,
      container = Container.elf,
      entry = "_start",
      output = "profile-cli",
    ),
  ],
)
