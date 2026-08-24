main := fn() -> u64 {
  42
}

## The manifest's entry symbol, supplied by `@export` (the entry is a linker symbol the author chooses).
launch := @export("launch") fn() {
  exit(main())
}

## A second entry the PROGRAM declares for itself — the conventional ELF `_start`, which the compiler
## honours whatever the manifest names. The test artifact links neither of the two.
_start := fn() {
  exit(main())
}

@test("named entry is not linked into the test artifact")
entry_excluded := fn() -> Result(usize, str) {
  if main() != 42 { return Result.Err("main did not return 42") }
  return Result.Ok(0)
}
