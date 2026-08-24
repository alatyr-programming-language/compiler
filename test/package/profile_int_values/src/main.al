main := fn() -> u64 {
  comptime if build.opt == 7 {
    comptime if build.opt != 8 { return 7 } else { return 0 }
  } else {
    comptime if build.opt == 42 {
      comptime if build.opt != 7 { return 42 } else { return 0 }
    } else { return 0 }
  }
}
