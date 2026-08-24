Mode := enum { slow, fast }
main := fn() -> u64 {
  comptime if build.word == "alpha beta" {
    comptime if build.mode == Mode.slow {
      comptime if build.profile == "debug" { return 11 } else { return 4 }
    } else { return 5 }
  } else {
    comptime if build.word == "release ca" {
      comptime if build.mode == Mode.fast { return 42 } else { return 6 }
    } else { return 3 }
  }
}
