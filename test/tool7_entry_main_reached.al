## TOOL-7 — `main` is an ORDINARY function in the test artifact, present because a test REACHES it
## under the normal reachability rules (it is not the entry: this program declares its own `_start`,
## which the test artifact excludes). The test passes only if the linked `main` really runs and returns
## its 42, so a dropped or mis-linked `main` fails the test rather than passing silently.
main := fn() -> u64 {
  42
}

_start := fn() {
  exit(main())
}

@test("a test reaches main")
calls_main := fn() -> Result(usize, str) {
  if main() != 42 { return Result.Err("main did not return 42") }
  return Result.Ok(0)
}
