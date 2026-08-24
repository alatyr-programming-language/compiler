main := fn() -> u64 {
  42
}

## The package's declared entry (the manifest's `Target.entry`). Absent from the test artifact.
_start := fn() {
  exit(main())
}

@test("package entry is not linked into the test artifact")
entry_excluded := fn() -> Result(usize, str) {
  if main() != 42 { return Result.Err("main did not return 42") }
  return Result.Ok(0)
}
