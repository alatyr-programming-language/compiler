## TOOL-7 focused package seam: this is a single-file package, so `package.al` is both the
## manifest and the anonymous package-root module. The package declares its `_start` through the
## spec-valid exact-export form `@export("_start") package_start`; `alatyr test` must replace that
## package entry with the test runner's `_start`, while a test-reached `main` and an unrelated
## `@export` root remain available in the test artifact. Production build/run must retain the entry.
app := Package(
  version = "0.1.0",
  target_dir = "target",
  targets = [
    Target(
      arch = Arch.x86_64,
      os = Os.linux,
      env = Env.gnu,
      container = Container.elf,
      entry = "_start",
      output = "test-entry-exclusion",
    ),
  ],
)

main := fn() -> u64 {
  42
}

@export("_start") package_start := fn() {
  exit(main())
}

@export("kept_export") kept := fn() -> u64 {
  17
}

@test("package _start is excluded while main and export remain")
entry_excluded := fn() -> Result(usize, str) {
  if main() != 42 { return Result.Err("main was not reachable") }
  return Result.Ok(0)
}
