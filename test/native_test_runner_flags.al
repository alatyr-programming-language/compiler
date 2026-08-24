@test("aaa pass before failure")
first := fn() -> Result(usize, str) {
  return Result.Ok(0)
}

@test("bbb trapped test")
trap_case := fn() {
  panic("trap")
}

@test("ccc after failure")
after := fn() -> Result(usize, str) {
  return Result.Ok(0)
}

@test("ddd soft failure")
soft := fn() -> u64 {
  return 1
}
