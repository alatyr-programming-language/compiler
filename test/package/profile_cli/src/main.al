main := fn() -> u64 {
  comptime if build.release_path {
    return 42
  } else {
    return 7
  }
}

@test("release profile reaches parallel test runner")
fn() {
  comptime if build.release_path {
    return
  } else {
    panic("release profile was not forwarded to alatyr test")
  }
}
