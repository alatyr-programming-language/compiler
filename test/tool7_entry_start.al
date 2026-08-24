## TOOL-7 — a program that declares its OWN entry (`_start`, the manifest `Target.entry` default) and
## also carries a `@test` item. The two artifacts exclude each other's part: `alatyr test` supplies the
## RUNNER's entry and does NOT link this `_start` (before TOOL-7 the assembler rejected the emitted
## assembly with "symbol `_start' is already defined", rc 13), while `alatyr build`/`run` keep this
## `_start` as the ELF entry and drop the `@test` item (TOOL-5). Built and run here for the BUILD half:
## the entry exits with `main()`'s 42 and no `__test` body reaches the executable.
main := fn() -> u64 {
  42
}

_start := fn() {
  exit(main())
}

@test("program with its own entry")
own_entry := fn() -> Result(usize, str) {
  return Result.Ok(0)
}
